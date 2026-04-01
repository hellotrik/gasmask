/***************************************************************************
 * EnvTreeItem
 *
 * Responsibilities:
 * - A lightweight tree model for NSOutlineView source list.
 * - Mirrors Gas Mask’s “group + item” UX: groups are not selectable.
 *
 * Items:
 * - Group: Profiles / Temp
 * - Leaf : EnvLayer
 ***************************************************************************/

#import <Foundation/Foundation.h>

@class EnvLayer;

@interface EnvTreeItem : NSObject

@property (nonatomic, readonly) BOOL isGroup;
@property (nonatomic, readonly) BOOL selectable;
@property (nonatomic, readonly) NSArray<EnvTreeItem *> *children;

@property (nonatomic, readonly) NSString *title;

// Leaf payload
@property (nonatomic, readonly) EnvLayer *layer;

+ (EnvTreeItem *)groupWithTitle:(NSString *)title children:(NSArray<EnvTreeItem *> *)children;
+ (EnvTreeItem *)leafWithLayer:(EnvLayer *)layer;

@end

