//
//  UIKit+Private.h
//  Reynard
//
//  Created by Minh Ton on 10/3/26.
//

#import <UIKit/UIKit.h>

typedef struct {
    UIRectEdge attachment;
    UIRectEdge alignment;
    CGFloat attachmentOffset;
    CGFloat alignmentOffset;
    NSInteger gravity;
} ContextMenuAnchor;

// [reynard-browser-zh] Weakly linked: the private class must not be a hard
// launch-time dependency on iOS 13, which predates the anchor customization.
API_AVAILABLE(ios(14.0))
@interface _UIContextMenuStyle : NSObject
+ (nonnull instancetype)defaultStyle;
@property(nonatomic) ContextMenuAnchor _preferredAnchor;
@end

@interface UIMenuElement (ReaderSettings)
@property(nonatomic, copy) NSAttributedString *attributedTitle;
@end

API_AVAILABLE(ios(15.0))
@interface UISheetPresentationControllerDetent (ReaderSettings)
+ (instancetype)_detentWithIdentifier:(NSString *)identifier
                             constant:(double)constant;
@end
