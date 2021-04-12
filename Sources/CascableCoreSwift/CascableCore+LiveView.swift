import Foundation
import CascableCore
import Combine
import ObjectiveC

extension LiveViewTerminationReason: Error {}

public extension CameraLiveView {

    @available(iOS 13.0, macOS 10.15, *)
    var liveViewPublisher: AnyPublisher<LiveViewFrame, LiveViewTerminationReason> {
        if let box = liveViewPublisherStorage { return box.publisher.eraseToAnyPublisher() }
        let publisher = LiveViewFramePublisher(for: self)
        liveViewPublisherStorage = LiveViewPublisherBox(publisher)
        return publisher.eraseToAnyPublisher()
    }
}

fileprivate var liveViewPublisherStorageObjCHandle: UInt8 = 0

fileprivate extension CameraLiveView {
    private var liveViewPublisherStorage: LiveViewPublisherBox? {
        get { return objc_getAssociatedObject(self, &liveViewPublisherStorageObjCHandle) as? LiveViewPublisherBox }
        set { objc_setAssociatedObject(self, &liveViewPublisherStorageObjCHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

fileprivate class LiveViewPublisherBox: NSObject {
    let publisher: LiveViewFramePublisher
    init(_ publisher: LiveViewFramePublisher) {
        self.publisher = publisher
    }
}

/// A Combine publisher that delivers live view frames.
@available(iOS 13.0, macOS 10.15, *)
public class LiveViewFramePublisher: Publisher {
    public typealias Output = LiveViewFrame
    public typealias Failure = LiveViewTerminationReason

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

    // TODO:
    // - Live view options
    // - Good documentation
    // - Test cases somehow
    // - Test multiple subscribers
    // - Threading and thread safety

    public init(for camera: CameraLiveView) {
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

    private func synchronized<T>(on lock: AnyObject, because reason: String, _ body: () throws -> T) rethrows -> T {
        objc_sync_enter(lock)
        defer { objc_sync_exit(lock) }
        return try body()
    }

    // MARK: Publisher API

    public func receive<S>(subscriber: S) where S: Subscriber, S.Input == LiveViewFrame, S.Failure == LiveViewTerminationReason {
        let subscription = LiveViewSubscription(subscriber: subscriber, publisher: self)
        synchronized(on: self, because: "Mutating subscriptions", { _fragile_subscriptions.add(subscription) })
        subscriber.receive(subscription: subscription)
    }

    // MARK: Camera API

    private func startLiveView() {
        guard let camera = camera else {
            handleLiveViewEnded(with: .failed)
            return
        }

        assert(!camera.liveViewStreamActive)

        let deliveryHandler: LiveViewFrameDelivery = { [weak self] frame, readyForNextFrame in
            self?.distributeLiveViewFrame(frame, nextFrameHandler: readyForNextFrame)
        }

        let terminationHandler: LiveViewTerminationHandler = { [weak self] reason, error in
            self?.handleLiveViewEnded(with: reason)
        }

        Swift.print("Starting live view")
        camera.beginStream(delivery: deliveryHandler, deliveryQueue: internalQueue,
                           options: [:], terminationHandler: terminationHandler)
    }

    private func endLiveView() {
        // TODO: We might want to be defensive about this being called multiple times.
        Swift.print("Stopping live view")
        camera?.endStream()
    }

    // MARK: Internal API

    fileprivate func handleUpdatedDemandFromSubscription(_ demand: Subscribers.Demand) {
        synchronized(on: self, because: "Updated demand can come from multiple threads at once") {

            Swift.print("Got updated demand: \(demand)")

            let demand = totalCurrentDemand()
            guard demand > .zero else { return }
            if demand == .unlimited { complainAboutUnlimitedDemand() }

            guard let camera = camera else {
                handleLiveViewEnded(with: .failed)
                return
            }

            // TODO: liveViewStreamActive can be async, so we might want to be defensive about that.
            if !camera.liveViewStreamActive {
                startLiveView()

            } else if let handler = pendingNextFrameHandler {
                // Live view is active and the camera is waiting for demand.
                Swift.print("Requesting frame due to updated demand")
                pendingNextFrameHandler = nil
                handler()
            } else {
                // Live view is active and we're already waiting for a frame. Nothing to do.
            }
        }
    }

    fileprivate func handleCancellationFromSubscription(_ subscription: LiveViewSubscriptionAPI) {
        synchronized(on: self, because: "Mutating subscriptions") {
            _fragile_subscriptions.remove(subscription)
            if activeSubscriptions.isEmpty { endLiveView() }
        }
    }

    // MARK: Cancellations

    private func handleLiveViewEnded(with reason: LiveViewTerminationReason) {
        activeSubscriptions.forEach({ $0.deliverLiveViewEndedReason(reason) })
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
            Swift.print("Requesting frame immediately after delivery due to continued demand")
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
fileprivate protocol LiveViewSubscriptionAPI: Combine.Subscription, AnyObject {
    /// Returns the current pending demand for the subscription.
    var currentDemand: Subscribers.Demand { get }
    /// Deliver a frame, returning the subscription's total pending demand _after_ the frame has been delivered.
    func deliverFrame(_ frame: LiveViewFrame) -> Subscribers.Demand
    /// Deliver a live view ended event to the subscriber.
    func deliverLiveViewEndedReason(_ reason: LiveViewTerminationReason)
}

// A subscription to the live view publisher. Very simple — most logic is in the publisher.
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
        publisher?.handleUpdatedDemandFromSubscription(currentDemand)
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

public extension Publisher {

    func sinkWithReadyHandler(receiveCompletion: @escaping DemandOnReadyHandlerSubscriber<Output, Failure>.CompletionDelivery,
                              receiveValue: @escaping DemandOnReadyHandlerSubscriber<Output, Failure>.ValueDelivery) -> AnyCancellable {

        let subscriber = DemandOnReadyHandlerSubscriber(receiveCompletion: receiveCompletion, receiveValue: receiveValue)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}

public extension Publisher where Failure == Never {

    func sinkWithReadyHandler(receiveValue: @escaping DemandOnReadyHandlerSubscriber<Output, Failure>.ValueDelivery) -> AnyCancellable {
        let subscriber = DemandOnReadyHandlerSubscriber<Output, Failure>(receiveValue: receiveValue)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}

public class DemandOnReadyHandlerSubscriber<Input, Failure>: Subscriber, Cancellable where Failure: Error {
    public typealias ValueDelivery = (_ value: Input, _ readyForMoreValues: @escaping () -> Void) -> Void
    public typealias CompletionDelivery = (Subscribers.Completion<Failure>) -> Void

    init(receiveCompletion: @escaping CompletionDelivery, receiveValue: @escaping ValueDelivery) where Failure: Error {
        self.receiveValue = receiveValue
        self.receiveCompletion = receiveCompletion
    }

    init(receiveValue: @escaping ValueDelivery) where Failure == Never {
        self.receiveValue = receiveValue
        self.receiveCompletion = { _ in }
    }

    deinit { cancel() }

    // MARK: Receiving Values

    private(set) var receiveValue: ValueDelivery
    private(set) var receiveCompletion: CompletionDelivery
    private var subscription: Subscription?

    public func receive(subscription: Subscription) {
        self.subscription = subscription
        // We always want to request some demand when subscribing, otherwise we'll
        // never have an opportunity to request more.
        subscription.request(.max(1))
    }

    public func receive(_ input: Input) -> Subscribers.Demand {
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

    public func receive(completion: Subscribers.Completion<Failure>) where Failure: Error {
        receiveCompletion(completion)
    }

    public func cancel() {
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
