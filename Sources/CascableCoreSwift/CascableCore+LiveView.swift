import Foundation
import CascableCore
import Combine
import ObjectiveC

extension LiveViewTerminationReason: Error {}

// MARK: - Public API

public struct LiveViewOption: RawRepresentable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// If set to `true`, image data will not be decoded in delivered live view frames, so the `image` property of
    /// delivered frames will be `nil`. All other properties will be populated as normal, including `rawImageData`.
    /// This can be useful if you have a frame rendering pipeline that doesn't need `NSImage`/`UIImage` objects,
    /// as turning off image decoding can save a significant amount of CPU resources.
    ///
    /// When omitted from the options dictionary, the assumed value for this option is `false`.
    public static let skipImageDecoding = LiveViewOption(rawValue: CBLLiveViewOptionSkipImageDecoding)

    /// If set to `true` and if supported by the particular camera model you're connected to, live view will be
    /// configured to favour lower-quality image data in an attempt to achieve a higher live view frame rate.
    /// If set to `false` (or omitted), live view will be configured to favour the highest quality image.
    ///
    /// Setting this option after live view has started will have no effect until live view is restarted.
    ///
    /// When omitted from the options dictionary, the assumed value for this option is `false`.
    public static let favorHighFrameRate = LiveViewOption(rawValue: CBLLiveViewOptionFavorHighFrameRate)
}

public extension Dictionary where Key == LiveViewOption, Value == Bool {

    /// Converts the dictionary of `LiveViewOption` into an ObjC/CascableCore-compatible options dictionary.
    var asCascableCoreLiveViewOptions: [String: Any] {
        return reduce(into: [String: Any](), { $0[$1.key.rawValue] = $1.value })
    }
}

public extension CameraLiveView {

    /// Returns the live view frame publisher for the camera without modifying any live view options.
    ///
    /// - Important: Frames will be generated on an arbitrary background queue. Use an explicit Combine scheduler to
    ///              get them where they need to be.
    @available(iOS 13.0, macOS 10.15, *)
    var liveViewPublisher: AnyPublisher<LiveViewFrame, LiveViewTerminationReason> {
        return liveViewPublisher(options: [:])
    }

    /// Returns the live view frame publisher for the camera, applying the given options.
    ///
    /// - Note: Since there is only one live view frame publisher per camera, options applied here will affect other
    ///         subscriptions to the camera's live view frame publisher. Use the `liveViewPublisher` to get the
    ///         publisher without affecting others, or pass an empty dictionary here.
    ///
    /// - Important: Frames will be generated on an arbitrary background queue. Use an explicit Combine scheduler to
    ///              get them where they need to be.
    ///
    /// - Parameter options: The options to apply.
    @available(iOS 13.0, macOS 10.15, *)
    func liveViewPublisher(options: [LiveViewOption: Bool]) -> AnyPublisher<LiveViewFrame, LiveViewTerminationReason> {
        let publisher = getOrCreateLiveViewPublisher()
        publisher.applyOptions(options)
        return publisher.eraseToAnyPublisher()
    }

    /// Apply the given options to the live view frame publisher.
    ///
    /// - Note: Since there is only one live view frame publisher per camera, options applied here will affect all
    ///         subscriptions to the camera's live view frame publisher.
    ///
    /// - Parameter options: The options to apply. Options not present will not be modified.
    @available(iOS 13.0, macOS 10.15, *)
    func applyLiveViewOptions(_ options: [LiveViewOption: Bool]) {
        getOrCreateLiveViewPublisher().applyOptions(options)
    }
}

public extension Publisher {

    /// Attaches a subscriber with closure-based and controlled demand behaviour.
    ///
    /// This method creates the subscriber and immediately requests a single value, prior to returning the subscriber.
    /// The return value should be held, otherwise the stream will be canceled. To request more values, call the
    /// `readyForMoreValues` closure provided by the `receiveValue` closure — doing so will request another value.
    ///
    /// - Parameters:
    ///   - receiveCompletion: The closure to execute when the publisher completes.
    ///   - receiveValue: The closure to execute on receipt of a value.
    ///
    /// - Returns: A cancellable instance, which you use when you end assignment of the received value.
    ///            Deallocation of the result will tear down the subscription stream.
    func sinkWithReadyHandler(receiveCompletion: @escaping (Subscribers.Completion<Failure>) -> Void,
                              receiveValue: @escaping (_ value: Output, _ readyForMoreValues: @escaping () -> Void) -> Void) -> AnyCancellable {

        let subscriber = DemandOnReadyHandlerSubscriber(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}

public extension Publisher where Failure == Never {

    /// Attaches a subscriber with closure-based and controlled demand behaviour.
    ///
    /// This method creates the subscriber and immediately requests a single value, prior to returning the subscriber.
    /// The return value should be held, otherwise the stream will be canceled. To request more values, call the
    /// `readyForMoreValues` closure provided by the `receiveValue` closure — doing so will request another value.
    ///
    /// - Parameters:
    ///   - receiveValue: The closure to execute on receipt of a value.
    ///
    /// - Returns: A cancellable instance, which you use when you end assignment of the received value.
    ///            Deallocation of the result will tear down the subscription stream.
    func sinkWithReadyHandler(receiveValue: @escaping (_ value: Output, _ readyForMoreValues: @escaping () -> Void) -> Void) -> AnyCancellable {
        let subscriber = DemandOnReadyHandlerSubscriber<Output, Failure>(receiveValue: receiveValue)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}

// MARK: - Camera Implementation Details

fileprivate var liveViewPublisherStorageObjCHandle: UInt8 = 0

fileprivate extension CameraLiveView {

    // We only want one publisher per camera instance.
    @available(iOS 13.0, macOS 10.15, *)
    func getOrCreateLiveViewPublisher() -> LiveViewFramePublisher {
        if let box = liveViewPublisherStorage {
            return box.publisher
        } else {
            let publisher = LiveViewFramePublisher(for: self)
            liveViewPublisherStorage = LiveViewPublisherBox(publisher)
            return publisher
        }
    }

    private var liveViewPublisherStorage: LiveViewPublisherBox? {
        get { return objc_getAssociatedObject(self, &liveViewPublisherStorageObjCHandle) as? LiveViewPublisherBox }
        set { objc_setAssociatedObject(self, &liveViewPublisherStorageObjCHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

@available(iOS 13.0, macOS 10.15, *)
fileprivate class LiveViewPublisherBox: NSObject {
    let publisher: LiveViewFramePublisher
    init(_ publisher: LiveViewFramePublisher) {
        self.publisher = publisher
    }
}

// MARK: - Custom Combine Types

/// A Combine publisher that delivers live view frames.
@available(iOS 13.0, macOS 10.15, *)
fileprivate class LiveViewFramePublisher: Publisher {
    typealias Output = LiveViewFrame
    typealias Failure = LiveViewTerminationReason

    /*
     Camera live view is a _very_ heavy operation, and there's only one physical camera that's supplying frames.
     As such, most of the work is done in a centralised publisher object, rather than the logic being in the
     subscription class live with property publishers. It's up to the API provider to ensure there's only one
     instance of this publisher per camera object.

     This publisher works by keeping an aggregate count of the demand from all of its subscribers, and asking the
     camera for new frames should the demand be more than zero. Since fetching frames requires a round trip to
     a physical piece of hardware and a decent chunk of CPU time to decode them, it's *strongly* recommended to
     use a Subscriber that sensibly deals with demand, rather than simply doling out an unlimited demand right
     away — if you do this and filter frames later, you're spending a large amount of resources to get frames just
     to discard them. Proper demand management is a much better approach.

     Camera live view will be started once the first non-zero demand comes from a subscriber, and will be stopped
     once the last subscriber is cancelled.
     */

    init(for camera: CameraLiveView) {
        self.camera = camera
        self.internalQueue = DispatchQueue(label: "CascableCore Live View Combine Publisher",
                                           qos: .default, attributes: [], autoreleaseFrequency: .workItem,
                                           target: .global(qos: .default))
    }

    private weak var camera: CameraLiveView?
    private let internalQueue: DispatchQueue

    private var _fragile_subscriptions = NSHashTable<AnyObject>.weakObjects()
    // NSHashTable doesn't like holding protocol types, even though they're declared `AnyObject` :(
    private var activeSubscriptions: [LiveViewSubscriptionAPI] {
        return synchronized(on: self, because: "Accessing subscribers", {
            return _fragile_subscriptions.allObjects.compactMap({ $0 as? LiveViewSubscriptionAPI })
        })
    }

    // This is for subscriptions incoming while live view is being torn down.
    private var _fragile_pendingSubscriptions: [LiveViewSubscriptionAPI] = []

    private func synchronized<T>(on lock: AnyObject, because reason: String, _ body: () throws -> T) rethrows -> T {
        objc_sync_enter(lock)
        defer { objc_sync_exit(lock) }
        return try body()
    }

    // MARK: Publisher API

    func receive<S>(subscriber: S) where S: Subscriber, S.Input == LiveViewFrame, S.Failure == LiveViewTerminationReason {
        let subscription = LiveViewSubscription(subscriber: subscriber, publisher: self)

        synchronized(on: self, because: "Mutating subscriptions", {
            if isEndingLiveView {
                // If we're in the process of stopping live view, we need to wait for that to complete
                // before we can accept subscribers/demand and start live view again.
                _fragile_pendingSubscriptions.append(subscription)
            } else {
                _fragile_subscriptions.add(subscription)
            }
        })

        subscriber.receive(subscription: subscription)
    }

    // MARK: Options

    private var liveViewOptions: [LiveViewOption: Bool] = [:]

    func applyOptions(_ options: [LiveViewOption: Bool]) {
        // We don't want to replace existing values.
        options.forEach({ liveViewOptions[$0.key] = $0.value })
        if let camera = camera, camera.liveViewStreamActive {
            camera.applyStreamOptions(liveViewOptions.asCascableCoreLiveViewOptions)
        }
    }

    // MARK: Camera API

    // Starting and ending live view are async processes that can take some time (multiple seconds). To avoid
    // multiple subscribers trying to start/end live view multiple times, we put a flag against them.
    private var isStartingLiveView: Bool = false
    private var isEndingLiveView: Bool = false

    private func startLiveView() {
        guard !isStartingLiveView, let camera = camera else { return }
        isStartingLiveView = true

        assert(camera.liveViewStreamActive == false)
        _unprotected_startLiveView()
    }

    private func _unprotected_startLiveView(retryCount: Int = 0) {
        guard let camera = camera else {
            handleLiveViewEnded(with: .failed)
            return
        }

        let deliveryHandler: LiveViewFrameDelivery = { [weak self] frame, readyForNextFrame in
            guard let self = self else { return }
            if self.isStartingLiveView { self.isStartingLiveView = false }
            self.distributeLiveViewFrame(frame, nextFrameHandler: readyForNextFrame)
        }

        let terminationHandler: LiveViewTerminationHandler = { [weak self] reason, error in
            if reason == .failed, error?.asCascableCoreError == .deviceBusy, retryCount < 5 {
                // Some cameras don't like starting live view soon after being connected to. To handle
                // this for our subscribers, we can retry a few times for them.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?._unprotected_startLiveView(retryCount: retryCount + 1)
                }
                return
            }

            guard let self = self else { return }
            if self.isStartingLiveView { self.isStartingLiveView = false }
            if self.isEndingLiveView { self.isEndingLiveView = false }
            self.handleLiveViewEnded(with: reason)
        }

        camera.beginStream(delivery: deliveryHandler, deliveryQueue: internalQueue,
                           options: liveViewOptions.asCascableCoreLiveViewOptions,
                           terminationHandler: terminationHandler)
    }

    private var isWaitingToEndLiveView: Bool = false
    private func endLiveViewSoon() {
        // Because stopping/starting live view is _such_ a heavy operation, we want to guard against the case
        // where clients rebuilding their subscribers (i.e., by removing and immediately re-adding subscribers)
        // causes a big interruption in live view frames.
        guard let camera = camera else { return }
        guard !isWaitingToEndLiveView else { return }
        isWaitingToEndLiveView = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            self.isWaitingToEndLiveView = false
            if self.activeSubscriptions.isEmpty {
                self.isEndingLiveView = true
                camera.endStream()
            }
        }
    }

    // MARK: Internal API

    func handleUpdatedDemand(_ demand: Subscribers.Demand, from subscription: LiveViewSubscriptionAPI) {
        synchronized(on: self, because: "Updated demand can come from multiple threads at once", {
            if _fragile_pendingSubscriptions.contains(where: { $0 === subscription }) {
                // Ignore demand for pending subscriptions at the moment.
                return
            }

            let demand = totalCurrentDemand()
            guard demand > .zero else { return }
            if demand == .unlimited { complainAboutUnlimitedDemand() }

            guard let camera = camera else {
                handleLiveViewEnded(with: .failed)
                return
            }

            if !camera.liveViewStreamActive {
                if !isStartingLiveView { startLiveView() }

            } else if let handler = pendingNextFrameHandler {
                // Live view is active and the camera is waiting for demand.
                pendingNextFrameHandler = nil
                handler()
            } else {
                // Live view is active and we're already waiting for a frame. Nothing to do.
            }
        })
    }

    func handleCancellationFromSubscription(_ subscription: LiveViewSubscriptionAPI) {
        synchronized(on: self, because: "Mutating subscriptions", {
            _fragile_subscriptions.remove(subscription)
            _fragile_pendingSubscriptions.removeAll(where: { $0 === subscription })
            if activeSubscriptions.isEmpty { endLiveViewSoon() }
        })
    }

    // MARK: Cancellations

    private func handleLiveViewEnded(with reason: LiveViewTerminationReason) {
        pendingNextFrameHandler = nil
        activeSubscriptions.forEach({ $0.deliverLiveViewEndedReason(reason) })

        // If we have pending subscribers (i.e., subscriptions were added while live view was in the process
        // of being stopped), we should check demand and restart live view if it's nonzero. However, since
        // live view is a big, physical process doing so _immediately_ after we've been told it's stopped has
        // a very high chance of failure. So, we wait a moment for things to "settle down" before restarting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.synchronized(on: self, because: "Mutating subscribers", {
                if self.isEndingLiveView { return } // If live view is ending again, we'll get to try again later.
                guard !self._fragile_pendingSubscriptions.isEmpty else { return }
                self._fragile_pendingSubscriptions.forEach({ self._fragile_subscriptions.add($0) })
                self._fragile_pendingSubscriptions.removeAll()

                if self.totalCurrentDemand() > .none, let subscriber = self.activeSubscriptions.first {
                    self.handleUpdatedDemand(self.totalCurrentDemand(), from: subscriber)
                }
            })
        }
    }

    // MARK: Handling Demand

    private func totalCurrentDemand() -> Subscribers.Demand {
        activeSubscriptions.reduce(Subscribers.Demand.none) { $0 + $1.currentDemand }
    }

    private var pendingNextFrameHandler: (() -> Void)? = nil

    private func distributeLiveViewFrame(_ frame: LiveViewFrame, nextFrameHandler: @escaping () -> Void) {
        let remainingDemand = activeSubscriptions
            .filter({ $0.currentDemand > .zero })
            .reduce(into: .none) { $0 += $1.deliverFrame(frame) }

        if remainingDemand == .unlimited { complainAboutUnlimitedDemand() }

        if remainingDemand > .none {
            // If we continue to have demand, immediately request a new frame.
            nextFrameHandler()
        } else {
            // Some cameras ignore the "ready for next frame" handler, so we can throw away old ones.
            pendingNextFrameHandler = nextFrameHandler
        }
    }

    private var hasComplainedAboutUnlimitedDemand: Bool = false

    private func complainAboutUnlimitedDemand() {
        guard !hasComplainedAboutUnlimitedDemand else { return }
        Swift.print("----- WARNING: Unlimited demand requested from a camera live view publisher -----")
        Swift.print("Using most built-in subscribers (including .sink, .assign, etc) will immediately request unlimited")
        Swift.print("demand from publishers. Unlimited demand means the camera live view publisher has no choice but to")
        Swift.print("request frames as often as it can, which can cause serious performance problems if frames start")
        Swift.print("coming in faster than your subscriber can render them. To avoid this, use a subscriber that doesn't")
        Swift.print("issue unlimited demand. CascableCoreSwift provides two subscribers — .sinkWithReadyHandler and")
        Swift.print(".sinkTargetingDeliveryRate — to handle this. This warning won't be output again.")
        Swift.print("---------------------------------------------------------------------------------")
        hasComplainedAboutUnlimitedDemand = true
    }
}

// MARK: -

// Type-erasure for `LiveViewSubscription`.
@available(iOS 13.0, macOS 10.15, *)
fileprivate protocol LiveViewSubscriptionAPI: Combine.Subscription, AnyObject {
    /// Returns the current pending demand for the subscription.
    var currentDemand: Subscribers.Demand { get }
    /// Deliver a frame, returning the subscription's total pending demand _after_ the frame has been delivered.
    func deliverFrame(_ frame: LiveViewFrame) -> Subscribers.Demand
    /// Deliver a live view ended event to the subscriber.
    func deliverLiveViewEndedReason(_ reason: LiveViewTerminationReason)
}

// A subscription to the live view publisher. Very lightweight — most logic is in the publisher.
@available(iOS 13.0, macOS 10.15, *)
fileprivate final class LiveViewSubscription<Subscriber>: Combine.Subscription, LiveViewSubscriptionAPI
    where Subscriber: Combine.Subscriber, Subscriber.Failure == LiveViewTerminationReason, Subscriber.Input == LiveViewFrame {

    private let subscriber: Subscriber
    private weak var publisher: LiveViewFramePublisher?

    fileprivate init(subscriber: Subscriber, publisher: LiveViewFramePublisher) {
        self.subscriber = subscriber
        self.publisher = publisher
    }

    private(set) var currentDemand: Subscribers.Demand = .none

    func request(_ demand: Subscribers.Demand) {
        currentDemand += demand
        publisher?.handleUpdatedDemand(currentDemand, from: self)
    }

    func deliverFrame(_ frame: LiveViewFrame) -> Subscribers.Demand {
        currentDemand -= 1
        currentDemand += subscriber.receive(frame)
        return currentDemand
    }

    func deliverLiveViewEndedReason(_ reason: LiveViewTerminationReason) {
        subscriber.receive(completion: reason == .endedNormally ? .finished : .failure(reason))
    }

    func cancel() {
        publisher?.handleCancellationFromSubscription(self)
    }
}

// MARK: - Custom Subscribers

@available(iOS 13.0, macOS 10.15, *)
fileprivate class DemandOnReadyHandlerSubscriber<Input, Failure>: Subscriber, Cancellable where Failure: Error {
    typealias ValueDelivery = (_ value: Input, _ readyForMoreValues: @escaping () -> Void) -> Void
    typealias CompletionDelivery = (Subscribers.Completion<Failure>) -> Void

    init(receiveCompletion: @escaping CompletionDelivery, receiveValue: @escaping ValueDelivery) where Failure: Error {
        self.receiveValue = receiveValue
        self.receiveCompletion = receiveCompletion
    }

    init(receiveValue: @escaping ValueDelivery) where Failure == Never {
        self.receiveValue = receiveValue
        self.receiveCompletion = { _ in }
    }

    deinit {
        #if DEBUG
        completionHandlerNotUsedWarningTimer?.invalidate()
        #endif
        cancel()
    }

    // MARK: Receiving Values

    private(set) var receiveValue: ValueDelivery
    private(set) var receiveCompletion: CompletionDelivery
    private var subscription: Subscription?

    func receive(subscription: Subscription) {
        self.subscription = subscription
        // We always want to request some demand when subscribing, otherwise we'll
        // never have an opportunity to request more.
        subscription.request(.max(1))
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        receiveValue(input, { [weak self] in
            #if DEBUG
            self?.resetCompletionHandlerWarning()
            #endif
            self?.subscription?.request(.max(1))
        })
        #if DEBUG
        startCompletionHandlerMisuseTimer()
        #endif
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) where Failure: Error {
        receiveCompletion(completion)
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    // MARK: Debug

    #if DEBUG
    private var completionHandlerNotUsedWarningTimer: Timer?
    private var hasComplainedAboutCompletionHandlerMisuse: Bool = false

    private func resetCompletionHandlerWarning() {
        completionHandlerNotUsedWarningTimer?.invalidate()
        completionHandlerNotUsedWarningTimer = nil
    }

    private func startCompletionHandlerMisuseTimer() {
        guard !hasComplainedAboutCompletionHandlerMisuse else { return }
        resetCompletionHandlerWarning()
        completionHandlerNotUsedWarningTimer = Timer.init(timeInterval: 5.0, repeats: false, block: { [weak self] timer in
            Swift.print("----- WARNING: Ready handler closure not called after 5 seconds -----")
            Swift.print("Using the .sinkWithReadyHandler operator on Publisher requires that the ready handler closure")
            Swift.print("is called after a value delivery. If this closure is not called, no further demand will be")
            Swift.print("issued, and no further values will be received. This warning won't be output again.")
            Swift.print("--------------------------------------------------------------------")
            self?.hasComplainedAboutCompletionHandlerMisuse = true
        })
        RunLoop.main.add(completionHandlerNotUsedWarningTimer!, forMode: .common)
    }
    #endif
}
