//
//  UIGlassEffect+Private.swift
//  Reynard
//
//  Created by Minh Ton on 8/8/26.
//

import UIKit

@available(iOS 26.0, *)
extension UIGlassEffect {
    // Disable the adaptive effect of UIGlassEffect to prevent it from changing its appearance
    // based on the underlying content
    static func nonAdaptive(style: Style) -> UIGlassEffect {
        let effect = UIGlassEffect(style: style)
        // Private glass selectors are not an ABI contract. Use the public effect
        // on newer systems rather than calling an implementation with an unknown ABI.
        if #available(iOS 27.0, *) {
            return effect
        }
        let glassSelector = Selector(("glass"))
        guard effect.responds(to: glassSelector) else { return effect }
        typealias GlassGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        let getGlass = unsafeBitCast(effect.method(for: glassSelector), to: GlassGetter.self)
        guard let glass = getGlass(effect, glassSelector)?.takeUnretainedValue() else { return effect }

        let adaptiveSelector = Selector(("setAdaptive:"))
        guard glass.responds(to: adaptiveSelector) else { return effect }
        typealias SetAdaptive = @convention(c) (AnyObject, Selector, Bool) -> Void
        let setAdaptive = unsafeBitCast(glass.method(for: adaptiveSelector), to: SetAdaptive.self)
        setAdaptive(glass, adaptiveSelector, false)

        let factorySelector = Selector(("effectWithGlass:"))
        guard let factoryMethod = class_getClassMethod(UIGlassEffect.self, factorySelector) else { return effect }
        typealias GlassEffectFactory = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
        let makeGlassEffect = unsafeBitCast(method_getImplementation(factoryMethod), to: GlassEffectFactory.self)
        return makeGlassEffect(UIGlassEffect.self, factorySelector, glass)?.takeUnretainedValue() as? UIGlassEffect ?? effect
    }
}
