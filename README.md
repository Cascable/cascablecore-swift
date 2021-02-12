## CascableCoreSwift

CascableCoreSwift is a Swift package that provides a better, more "Swift-y" API for [CascableCore](https://github.com/cascable/cascablecore-binaries/).

This package is currently in very early alpha, and depends on an alpha version of CascableCore.

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

If you're a fan of [Combine](https://developer.apple.com/documentation/combine), this package provides a combine publisher for property values. 

#### Basic Usage

There are two APIs added to `Camera`, which are convenience methods for creating publishers for camera values or valid settable values. For example:

``` swift
camera.valuePublisher(for: .shutterSpeed).sink { shutterSpeed in 
    print("The current shutter speed is: \(shutterSpeed?.localizedDisplayValue ?? "nil")")
}

camera.settableValuesPublisher(for: .shutterSpeed).sink { shutterSpeeds in 
    print("Valid shutter speeds are: \(shutterSpeeds.compactMap({ $0.localizedDisplayValue }))")
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

