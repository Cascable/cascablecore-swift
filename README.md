## CascableCoreSwift

CascableCoreSwift is a Swift package that provides better, more "Swift-y" APIs for [CascableCore](https://github.com/cascable/cascablecore-distribution/) — an SDK for working with over 200 models of DSLR and mirrorless cameras. This package is additive in that it adds to the existing CascableCore APIs rather than replacing it.

- For more information on the CascableCore product, including getting a trial license, see the [Cascable Developer Portal](https://developer.cascable.se/).

- The best starting point for working with the SDK is by seeing CascableCore in action by checking out the [CascableCore Demo Projects](https://github.com/Cascable/cascablecore-demo) repository. You'll need a trial license for it to do anything useful!

- Next, our [Getting Started With CascableCore](https://github.com/Cascable/cascablecore-demo/blob/master/Getting%20Started%20With%20CascableCore.md) document contains discussion about the CascableCore APIs and concepts in the order in which you're likely to encounter them. These APIs and concepts are equally important for both Objective-C and Swift developers.

### Contents

- [Strongly-Typed Property API](#strongly-typed-property-api)
- [Combine Publishers](#combine-publishers)
    - [Basic Usage](#basic-usage)
    - [Live View](#live-view)
- [Metal-Backed Live View Rendering View Controller](#metal-backed-live-view-rendering-view-controller)
- [Manual Camera Discovery](#strongly-typed-property-api)


### Strongly-Typed Property API

This package adds a strongly-typed property API to `Camera`, allowing much nicer property-manipulating code to be written in Swift. The API is largely similar to the new Objective-C version introduced in CascableCore 10.0, except for the following:

- Key-Value Observing cannot be used.

- There is no special "exposure" property type, and no `currentExposureValue` property. Instead, such properties are simply strongly-typed with an exposure type, and `commonValue` returns the exposure value.

- `commonValue` can now return `nil` (instead of `PropertyCommonValueNone`).

For example:

``` swift
let isoProperty = camera.property(for: .iso) // Gives you a `TypedCameraProperty<ISOValue>`
print("ISO is: \(isoProperty.currentValue.localizedDisplayValue)")

// Because properties are strongly-typed, we can do nice logic.
if isoProperty?.commonValue == .iso100 { print("ISO 100!") }

// Important: The observation will invalidate when this token is 
// deallocated — it should be stored somewhere!
let observerToken = property.addObserver { property, changeType in
    if changeType.contains(.value) { 
       print("ISO changed to: \(property.currentValue.localizedDisplayValue)!")
    }
    
    if changeType.contains(.validSettableValues) {
        print("Valid ISOs changed to: \(property.validSettableValues.compactMap({ $0.localizedDisplayValue }))!")
    }
}
```

For documentation on the new property API introduced with CascableCore 10.0, see the documentation in CascableCore.

### Combine Publishers

If you're a fan of [Combine](https://developer.apple.com/documentation/combine), this package provides Combine publishers for property values, camera live view, and other miscellaneous camera state. 

#### Basic Usage

There are APIs added to `Camera` which are convenience methods for creating publishers for camera values or valid settable values. For example:

``` swift
camera.publisher(for: .shutterSpeed).sink { shutterSpeedProperty in
    // Fires whenever the current value or valid settable values change.
}

camera.valuePublisher(for: .shutterSpeed).sink { shutterSpeed in
    // Fires whenever the current value changes.
    print("The current shutter speed is: \(shutterSpeed?.localizedDisplayValue ?? "nil")")
}

camera.settableValuesPublisher(for: .shutterSpeed).sink { shutterSpeeds in 
    // Fires whenever the valid settable values change.
    print("Valid shutter speeds are: \(shutterSpeeds.compactMap({ $0.localizedDisplayValue }))")
}
```

Also added are a few convenience publishers for various camera state properties. You can find them all in `CascableCore+Combine.swift`.

``` swift
camera.videoRecordingStatePublisher().sink { recordingState in
    switch recordingState {
    case .notRecording: label.text = "Not Recording"
    case .recording(let timer?): label.text = "Recording: \(timer.asMinutesAndSeconds)"
    case .recording(_): label.text = "Recording"
    }
}
```

Also included is a general-purpose helper for "flattening" combined publishers, called `.flatten()`. For example: 

``` swift
camera.valuePublisher(for: .shutterSpeed)
    .combineLatest(camera.valuePublisher(for: .aperture))
    .combineLatest(camera.valuePublisher(for: .iso))
    .flatten()
    .sink { shutter, aperture, iso in
        print("Exposure triangle values: \(shutter), \(aperture), \(iso)")
    }
```

#### Live View

Due to the nature of live view, its publisher has some usage considerations to be aware of. In particular: 

- Starting and stopping live view is a very heavy, multi-second long operation.

- Live view frames are very expensive to get, each requiring a round-trip to the hardware camera and a decent amount of CPU resources to decode. They can also come in very fast, sometimes faster than can be reasonably rendered on-screen.

- There is only a single source of live view frames: the connected piece of camera hardware.

With these limitations in mind, there can only be one Combine live view publisher per camera instance. Additional calls to the `liveViewPublisher` property or `liveViewPublisher(options:)` method will always return the same publisher for any given camera. This means that options applied to the publisher via `liveViewPublisher(options:)` or `applyLiveViewOptions(_:)` will affect all subscribers to a camera's live view publisher.

The live view frame publisher will start camera live view when the first demand is issued from a subscriber, and will be turned off shortly after the last subscriber is removed — this allows clients to rebuild their subscribers without turning live view off and immediately back on again.

To manage frame pacing and resource management, the live view publisher uses Combine's `Demand` concept. Unfortunately, Combine's default `.sink` and `.assign` subscriptions immediately issue an `.unlimited` amount of demand, and as such are very much discouraged for use with the live view publisher — without the ability to manage demand the publisher has no choice but to continuously request new frames, which can cause overly large amounts of CPU usage as well as buffer backfill if frames are coming in faster than they can be consumed. Unfortunately, Combine operators like `.throttle` don't manage demand in this way — `.throttle` simply drops values, so you'll be needlessly using a large amount of resources with a `.throttle` then a `.sink`.

Using any subscription that issues an `.unlimited` demand will cause the live view publisher to print a warning message to the console.

In order to mitigate this, `CascableCoreSwift` provides a new subscription method, very similar to `.sink`, that takes a completion handler to inform the subscription and publisher when it's appropriate to deliver more frames. To use it, call `.sinkWithReadyHandler` on a publisher, and make sure you call the ready handler when you're ready for more values. For example: 

``` swift
// In this example, we're processing the frame synchronously in the subscription closure.

camera.liveViewPublisher(options: [.skipImageDecoding: true])
    .receive(on: DispatchQueue.global(qos: .default))
    .sinkWithReadyHandler { completion in
        print("Live view ended with completion reason: \(completion)" )
    } receiveValue: { frame, readyForNextFrame in
        let result = processFrameSynchronously(frame)
        readyForNextFrame()
    }
    
// In this example, we're rendering the frame asynchronously and informing the subscription
// when we're done and ready for another frame.

camera.liveViewPublisher(options: [.skipImageDecoding: true])
    .receive(on: DispatchQueue.global(qos: .default))
    .sinkWithReadyHandler { completion in
        print("Live view ended with completion reason: \(completion)" )
    } receiveValue: { frame, readyForNextFrame in
        let result = processFrameSynchronously(frame)
        DispatchQueue.main.async {
            // Rendering an image to screen still takes some time.
            self.renderProcessedFrameOnScreen(result)
            readyForNextFrame()
        }
    }
```


### Metal-Backed Live View Rendering View Controller

Some cameras deliver high-framerate, high-quality live view streams that're a challenge to handle efficiently. For our app [Cascable Studio](https://cascable.se/studio/) we developed a rendering pipeline that uses Metal to keep live view rendering entirely on the GPU, significantly reducing resource usage and increasing performance compared to using solutions like `UIImageView`.

With CascableCore 16, we're excited to be able to open-source this for everyone to use!

Included is an easy-to-use Metal-backed `UIViewController` that you can use to display live view in your app. Simply create the view controller and place it into your UI as you would any other, then connect it to a camera's live view feed:

```swift
// Make sure you pass .skipImageDecoding since CascableCore's internal 
// decoding is CPU-based and resource-intensive.

camera.liveViewPublisher(options: [.skipImageDecoding: true])
    .receive(on: DispatchQueue.main)
    .sinkWithReadyHandler { completion in
        print("Live view ended with completion reason: \(completion)" )
    } receiveValue: { frame, readyForNextFrame in
        liveViewRendererView.render(frame: frame, completionHandler: { orientation, size in 
            // Sync the rest of your UI with the orientation etc.
            readyForNextFrame()
        })
    }
```

The underlying Metal rendering pipeline works on all platforms, while the view controller is currently only for UIKit-based platforms (i.e., everything except for AppKit-based macOS apps, including Mac Catalyst). If you have need for an AppKit view controller, please get in touch.


### Manual Camera Discovery

This package adds a nicer API for manual camera discovery, allowing quick creation of descriptors and a `Result<Camera, Error>`
result in the completion handler:


``` swift
let manualDiscovery = CameraDiscovery.shared.manualDiscovery

manualDiscovery.discover(.cameraAtSuggestedGateway(.canon)) { result in
    switch result {
    case .success(let camera):
        // Use the camera. Make sure you keep a strong reference to it!
    case .failure(let error):
        print("Couldn't resolve camera with error: \(error)")
    }
}

manualDiscovery.discover(.cameraType(.canon, atGatewayOfInterface: "en0")) { result in
    switch result {
    case .success(let camera):
        // Use the camera. Make sure you keep a strong reference to it!
    case .failure(let error):
        print("Couldn't resolve camera with error: \(error)")
    }
}
```

