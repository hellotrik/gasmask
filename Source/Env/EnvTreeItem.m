/***************************************************************************
 * EnvTreeItem implementation
 ***************************************************************************/

#import "EnvTreeItem.h"
#import "EnvLayer.h"

@interface EnvTreeItem ()
{
	BOOL _isGroup;
	BOOL _selectable;
	NSArray<EnvTreeItem *> *_children;
	NSString *_title;
	EnvLayer *_layer;
}
@end

@implementation EnvTreeItem

+ (EnvTreeItem *)groupWithTitle:(NSString *)title children:(NSArray<EnvTreeItem *> *)children
{
	EnvTreeItem *i = [EnvTreeItem new];
	i->_isGroup = YES;
	i->_selectable = NO;
	i->_title = [title copy];
	i->_children = [children copy] ?: @[];
	return i;
}

+ (EnvTreeItem *)leafWithLayer:(EnvLayer *)layer
{
	EnvTreeItem *i = [EnvTreeItem new];
	i->_isGroup = NO;
	i->_selectable = YES;
	i->_layer = layer;
	i->_title = [layer.name copy] ?: [layer.layerId copy];
	i->_children = @[];
	return i;
}

- (BOOL)isGroup { return _isGroup; }
- (BOOL)selectable { return _selectable; }
- (NSArray<EnvTreeItem *> *)children { return _children; }
- (NSString *)title { return _title; }
- (EnvLayer *)layer { return _layer; }

@end

