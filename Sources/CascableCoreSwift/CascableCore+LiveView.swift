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

    private weak var camera: CameraLiveView?

    // TODO: I think this should be a weak array — subscriptions get cancelled on deinit? (double-check)
    private var subscriptions: [LiveViewSubscriptionAPI] = []

    public init(for camera: CameraLiveView) {
        self.camera = camera
    }

    public func receive<S>(subscriber: S) where S: Subscriber, S.Input == LiveViewFrame, S.Failure == LiveViewTerminationReason {
        let subscription = LiveViewSubscription(subscriber: subscriber, publisher: self)
        subscriptions.append(subscription)
        subscriber.receive(subscription: subscription)
    }

    // MARK: - Camera API

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

        camera.beginStream(delivery: deliveryHandler, deliveryQueue: .global(qos: .userInteractive),
                           options: [:], terminationHandler: terminationHandler)
    }

    private func endLiveView() {
        // TODO: We might want to be defensive about this being called multiple times.
        camera?.endStream()
    }

    // MARK: - Internal API

    fileprivate func handleUpdatedDemandFromSubscription(_ demand: Subscribers.Demand) {
        // What if we're already waiting for a frame?
        Swift.print("Got updated demand: \(demand)")

        guard totalCurrentDemand() > .zero else { return }

        guard let camera = camera else {
            handleLiveViewEnded(with: .failed)
            return
        }

        // TODO: liveViewStreamActive can be async, so we might want to be defensive about that.
        if !camera.liveViewStreamActive {
            startLiveView()

        } else if let handler = pendingNextFrameHandler {
            // Live view is active and the camera is waiting for demand.
            pendingNextFrameHandler = nil
            handler()
        } else {
            // Live view is active and we're already waiting for a frame. Nothing to do.
        }
    }

    fileprivate func handleCancellationFromSubscription(_ subscription: LiveViewSubscriptionAPI) {
        subscriptions.removeAll(where: { $0 === subscription })
        if subscriptions.isEmpty { endLiveView() }
    }

    // MARK: - Cancellations

    private func handleLiveViewEnded(with reason: LiveViewTerminationReason) {
        subscriptions.forEach({ $0.deliverFailure(reason) })
    }

    // MARK: - Handling Demand

    private func totalCurrentDemand() -> Subscribers.Demand {
        subscriptions.reduce(Subscribers.Demand.none) { $0 + $1.currentDemand }
    }

    private var pendingNextFrameHandler: (() -> Void)? = nil

    private func distributeLiveViewFrame(_ frame: LiveViewFrame, nextFrameHandler: @escaping () -> Void) {
        let remainingDemand = subscriptions
            .filter({ $0.currentDemand > .zero })
            .reduce(into: .none) { $0 += $1.deliverFrame(frame) }

        if remainingDemand > .none {
            nextFrameHandler()
        } else {
            assert(pendingNextFrameHandler == nil)
            pendingNextFrameHandler = nextFrameHandler
        }
    }
}

fileprivate protocol LiveViewSubscriptionAPI: Combine.Subscription, AnyObject {
    /// Returns the current pending demand for the subscription.
    var currentDemand: Subscribers.Demand { get }
    /// Deliver a frame, returning the subscription's total pending demand _after_ the frame has been delivered.
    func deliverFrame(_ frame: LiveViewFrame) -> Subscribers.Demand
    /// Deliver a live view ended event to the subscriber.
    func deliverFailure(_ reason: LiveViewTerminationReason)
}

fileprivate final class LiveViewSubscription<Subscriber>: Combine.Subscription, LiveViewSubscriptionAPI
    where Subscriber: Combine.Subscriber, Subscriber.Failure == LiveViewTerminationReason, Subscriber.Input == LiveViewFrame {

    private let subscriber: Subscriber
    private var publisher: LiveViewFramePublisher?

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

    func deliverFailure(_ reason: LiveViewTerminationReason) {
        subscriber.receive(completion: reason == .endedNormally ? .finished : .failure(reason))
    }

    func cancel() {
        publisher?.handleCancellationFromSubscription(self)
    }
}



