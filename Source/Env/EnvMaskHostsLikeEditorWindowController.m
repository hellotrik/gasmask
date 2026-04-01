/***************************************************************************
 * EnvMaskHostsLikeEditorWindowController implementation
 ***************************************************************************/

#import "EnvMaskHostsLikeEditorWindowController.h"

#import "EnvStore.h"
#import "EnvResolver.h"
#import "EnvExporter.h"
#import "EnvOpsTextFormat.h"

static NSString *const kEnvTBCreate = @"com.gasmask.env.toolbar.create";
static NSString *const kEnvTBRemove = @"com.gasmask.env.toolbar.remove";
static NSString *const kEnvTBSave = @"com.gasmask.env.toolbar.save";
static NSString *const kEnvTBActivate = @"com.gasmask.env.toolbar.activate";
static NSString *const kEnvTBTerminal = @"com.gasmask.env.toolbar.terminal";

// 与 Editor.xib / EditorController 中 Gas Mask 主窗口分割条一致
#define kEnvSplitMinWidth 140.0
#define kEnvSplitMaxWidth 300.0
#define kEnvSplitDefaultWidth 160.0

@interface EnvMaskHostsLikeEditorWindowController () <NSToolbarDelegate, NSSplitViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>

@property (nonatomic) NSSplitView *splitView;
@property (nonatomic) NSTextField *statusTextField;

/// 扁平列表：Temp 固定第一行，其余 Profile 按 priority/名称排序（与 Gas Mask 侧栏类似的单层列表，无树）。
@property (nonatomic) NSTableView *sourceList;
@property (nonatomic) NSArray<EnvLayer *> *flatLayers;

@property (nonatomic) NSTextView *opsTextView;

@property (nonatomic) NSView *rightEditorView;
@property (nonatomic) NSScrollView *opsScrollView;

@property (nonatomic) NSArray<EnvLayer *> *layers;
@property (nonatomic) EnvLayer *selectedLayer;
@property (nonatomic) BOOL opsTextDirty;

@end

@implementation EnvMaskHostsLikeEditorWindowController

static EnvMaskHostsLikeEditorWindowController *sharedInstance = nil;

+ (EnvMaskHostsLikeEditorWindowController *)defaultInstance
{
	if (!sharedInstance) {
		sharedInstance = [[EnvMaskHostsLikeEditorWindowController alloc] initWithWindow:nil];
	}
	return sharedInstance;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSScrollView *)scrollViewWithView:(NSView *)view
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[sv setHasVerticalScroller:YES];
	[sv setAutohidesScrollers:YES];
	[sv setDocumentView:view];
	return sv;
}

/// 右侧与 Editor.xib 中 Hosts 文本区一致：整 pane 仅主编辑区（名称/优先级/启用在左侧列表与工具栏 Activate 中编辑）。
- (void)layoutRightEditorSubviews
{
	NSView *right = self.rightEditorView;
	if (!right) return;
	[self.opsScrollView setFrame:right.bounds];
	[self syncOpsTextViewGeometryToScrollView];
}

/// 对齐 Editor.xib：底栏状态行 + 上方为分割条区域（EditorController 用 contentBorderThickness 画底边）。
- (void)layoutEnvMaskWindowChrome
{
	NSWindow *w = self.window;
	NSView *cv = w.contentView;
	if (!cv || !self.splitView || !self.statusTextField) return;

	const CGFloat statusH = 18.0;
	NSRect b = cv.bounds;
	[self.statusTextField setFrame:NSMakeRect(0, 0, b.size.width, statusH)];
	[self.splitView setFrame:NSMakeRect(0, statusH, b.size.width, b.size.height - statusH)];
	[w setContentBorderThickness:statusH forEdge:NSMinYEdge];
}

/// 将 ops 文档视图铺满可视区（至少与 clip 同高），否则下方空白不属于 NSTextView，点击无法成为第一响应者、无法输入（含中文 IME）。
/// 注意：首帧或 split 未布局完时 sv.contentSize 可能为 0，需用 contentView.bounds.size 兜底（否则 sync 空跑，文档视图保持默认小尺寸）。
- (void)syncOpsTextViewGeometryToScrollView
{
	NSScrollView *sv = self.opsScrollView;
	NSTextView *tv = self.opsTextView;
	if (!sv || !tv) return;

	NSWindow *win = sv.window;
	if (win && win.contentView) {
		[win.contentView layoutSubtreeIfNeeded];
	}
	[sv layoutSubtreeIfNeeded];
	NSClipView *clip = sv.contentView;
	[clip layoutSubtreeIfNeeded];

	NSSize contentSize = sv.contentSize;
	if (contentSize.width < 1.0 || contentSize.height < 1.0) {
		contentSize = clip.bounds.size;
	}
	if (contentSize.width < 1.0 || contentSize.height < 1.0) {
		return;
	}

	[tv setHorizontallyResizable:NO];
	[tv setVerticallyResizable:YES];
	[tv setAutoresizingMask:NSViewWidthSizable];

	NSTextContainer *tc = tv.textContainer;
	tc.widthTracksTextView = YES;
	tc.containerSize = NSMakeSize(contentSize.width, CGFLOAT_MAX);

	[tv.layoutManager ensureLayoutForTextContainer:tc];
	NSRect used = [tv.layoutManager usedRectForTextContainer:tc];
	CGFloat inset = tv.textContainerInset.height * 2.0;
	CGFloat usedH = MAX(ceil(NSMaxY(used) + inset), 1.0);
	CGFloat clipH = contentSize.height;
	CGFloat docH = MAX(usedH, clipH);

	[tv setMinSize:NSMakeSize(contentSize.width, clipH)];
	[tv setMaxSize:NSMakeSize(contentSize.width, FLT_MAX)];

	NSRect r = tv.frame;
	r.origin = NSZeroPoint;
	r.size.width = contentSize.width;
	r.size.height = docH;
	[tv setFrame:r];
}

- (NSTextView *)newEditableOpsTextView
{
	NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[tv setEditable:YES];
	[tv setSelectable:YES];
	[tv setRichText:NO];
	[tv setFont:[NSFont userFixedPitchFontOfSize:12]];
	[tv setImportsGraphics:NO];
	[tv setAutoresizingMask:NSViewWidthSizable];
	[tv setDelegate:self];
	return tv;
}

- (void)loadOpsTextForSelectedLayer
{
	if (!self.selectedLayer) {
		self.opsTextView.string = @"";
		self.opsTextDirty = NO;
		[self syncOpsTextViewGeometryToScrollView];
		return;
	}
	self.opsTextView.string = [EnvOpsTextFormat textFromOps:(self.selectedLayer.ops ?: @[])];
	self.opsTextDirty = NO;
	[self syncOpsTextViewGeometryToScrollView];
}

/// 保存/切层时：若用户在文本框里改过，用文本解析结果，否则用已持久化的 ops。
- (NSArray<EnvVarOp *> *)resolvedOpsForPersist
{
	if (!self.selectedLayer) return @[];
	if (self.opsTextDirty) return [EnvOpsTextFormat opsFromText:self.opsTextView.string];
	return self.selectedLayer.ops ?: @[];
}

- (void)commitOpsTextForCurrentLayerIfDirty
{
	if (!self.selectedLayer || !self.opsTextDirty) return;

	NSArray<EnvVarOp *> *ops = [EnvOpsTextFormat opsFromText:self.opsTextView.string];
	EnvLayer *l = self.selectedLayer;
	NSInteger p = l.priority;
	NSString *name = l.name ?: @"";
	BOOL en = l.enabled;
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:name enabled:en priority:p ops:ops];

	NSMutableArray *layers = [self.layers mutableCopy];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		EnvLayer *x = layers[i];
		if ([x.layerId isEqualToString:l.layerId]) { layers[i] = nl; break; }
	}
	self.opsTextDirty = NO;
	[self persistLayers:layers];
}

- (void)saveOpsText:(id)sender
{
	if (!self.selectedLayer) return;
	self.opsTextDirty = YES;
	[self commitOpsTextForCurrentLayerIfDirty];
}

/// Temp 固定第一行，其余为 Profile；不含 base（内部层）。
- (NSArray<EnvLayer *> *)buildFlatRowsFromLayers:(NSArray<EnvLayer *> *)layers
{
	NSMutableArray<EnvLayer *> *profiles = [NSMutableArray array];
	EnvLayer *tempLayer = nil;
	for (EnvLayer *l in layers) {
		if ([l.layerId isEqualToString:@"base"]) continue;
		if ([l.layerId isEqualToString:@"temp"]) {
			tempLayer = l;
			continue;
		}
		[profiles addObject:l];
	}
	[profiles sortUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		return [a.name compare:b.name options:NSCaseInsensitiveSearch];
	}];
	NSMutableArray<EnvLayer *> *out = [NSMutableArray array];
	if (tempLayer) [out addObject:tempLayer];
	[out addObjectsFromArray:profiles];
	return [out copy];
}

- (NSInteger)rowIndexForLayerId:(NSString *)layerId
{
	if (!layerId) return -1;
	NSUInteger n = self.flatLayers.count;
	for (NSUInteger i = 0; i < n; i++) {
		if ([self.flatLayers[i].layerId isEqualToString:layerId]) return (NSInteger)i;
	}
	return -1;
}

- (void)reloadFromStore
{
	self.layers = [[EnvStore defaultInstance] ensureTempLayerExists];
	self.flatLayers = [self buildFlatRowsFromLayers:self.layers];
	[self.sourceList reloadData];

	if (!self.selectedLayer && self.flatLayers.count > 0) {
		NSUInteger row = 0;
		if (self.flatLayers.count > 1 && [self.flatLayers[0].layerId isEqualToString:@"temp"]) {
			row = 1;
		}
		[self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[self selectLayer:self.flatLayers[row]];
	}

	[self refreshPreview:nil];
}

- (void)selectLayer:(EnvLayer *)layer
{
	self.selectedLayer = layer;
	[self loadOpsTextForSelectedLayer];
	[self refreshPreview:nil];
}

- (EnvLayer *)layerById:(NSString *)layerId
{
	for (EnvLayer *l in self.layers) {
		if ([l.layerId isEqualToString:layerId]) return l;
	}
	return nil;
}

- (void)persistLayers:(NSArray<EnvLayer *> *)layers
{
	NSResponder *frBefore = self.window.firstResponder;
	BOOL opsWasFirst = (frBefore == self.opsTextView);

	[[EnvStore defaultInstance] saveLayers:layers error:NULL];
	self.layers = layers;
	self.flatLayers = [self buildFlatRowsFromLayers:layers];
	[self.sourceList reloadData];

	if (self.selectedLayer) {
		EnvLayer *updatedSelected = [self layerById:self.selectedLayer.layerId];
		if (updatedSelected) {
			NSInteger r = [self rowIndexForLayerId:updatedSelected.layerId];
			if (r >= 0) {
				[self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r] byExtendingSelection:NO];
			}
			[self selectLayer:updatedSelected];
		}
	}
	[self refreshPreview:nil];

	if (opsWasFirst && self.window) {
		[self.window makeFirstResponder:self.opsTextView];
	}
}

#pragma mark - Window

- (void)ensureWindow
{
	if (self.window) return;

	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 520)
											 styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
											   backing:NSBackingStoreBuffered
												 defer:NO];
	[w setTitle:@"EnvMask"];
	[w setMinSize:NSMakeSize(400, 400)];
	[w setFrameAutosaveName:@"envmask_editor_window"];
	[self setWindow:w];

	NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"com.gasmask.env.toolbar"];
	[tb setDelegate:self];
	[tb setAllowsUserCustomization:NO];
	[tb setDisplayMode:NSToolbarDisplayModeIconAndLabel];
	[tb setSizeMode:NSToolbarSizeModeRegular];
	[w setToolbar:tb];

	self.statusTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[self.statusTextField setBezeled:NO];
	[self.statusTextField setDrawsBackground:NO];
	[self.statusTextField setEditable:NO];
	[self.statusTextField setSelectable:NO];
	[self.statusTextField setAlignment:NSTextAlignmentCenter];
	[self.statusTextField setFont:[NSFont systemFontOfSize:11]];
	[self.statusTextField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

	CGRect cvb = w.contentView.bounds;
	const CGFloat statusH = 18.0;
	self.splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, statusH, cvb.size.width, cvb.size.height - statusH)];
	[self.splitView setVertical:YES];
	[self.splitView setDividerStyle:NSSplitViewDividerStyleThin];
	[self.splitView setDelegate:self];
	[self.splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[w.contentView addSubview:self.splitView];

	self.sourceList = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, kEnvSplitDefaultWidth, 400)];
	NSTableColumn *nameCol = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[nameCol setWidth:118];
	[nameCol setMinWidth:60];
	[[nameCol dataCell] setEditable:YES];
	NSTableColumn *prioCol = [[NSTableColumn alloc] initWithIdentifier:@"prio"];
	[prioCol setWidth:36];
	[prioCol setMinWidth:28];
	[[prioCol dataCell] setEditable:YES];
	[self.sourceList addTableColumn:nameCol];
	[self.sourceList addTableColumn:prioCol];
	[self.sourceList setHeaderView:nil];
	[self.sourceList setRowHeight:20.0];
	[self.sourceList setUsesAlternatingRowBackgroundColors:NO];
	[self.sourceList setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
	[self.sourceList setDelegate:self];
	[self.sourceList setDataSource:self];
	[self.sourceList setFocusRingType:NSFocusRingTypeNone];

	NSScrollView *leftSv = [self scrollViewWithView:self.sourceList];
	[leftSv setFocusRingType:NSFocusRingTypeNone];
	[leftSv setFrame:NSMakeRect(0, 0, kEnvSplitDefaultWidth, cvb.size.height - statusH)];
	[self.splitView addSubview:leftSv];

	NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(kEnvSplitDefaultWidth + [self.splitView dividerThickness], 0, 600, cvb.size.height - statusH)];
	[right setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	self.rightEditorView = right;
	[right setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutRightEditorSubviews) name:NSViewFrameDidChangeNotification object:right];

	self.opsTextView = [self newEditableOpsTextView];
	self.opsScrollView = [self scrollViewWithView:self.opsTextView];
	[self.opsScrollView setBorderType:NSNoBorder];
	[right addSubview:self.opsScrollView];

	[self.splitView addSubview:right];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutEnvMaskWindowChrome) name:NSWindowDidResizeNotification object:w];

	[w.contentView addSubview:self.statusTextField];

	[self layoutEnvMaskWindowChrome];
	[self layoutRightEditorSubviews];

	NSView *leftPane = [[self.splitView subviews] firstObject];
	CGFloat pos = leftPane ? NSWidth(leftPane.frame) : 0;
	if (pos > kEnvSplitMaxWidth) {
		[self.splitView setPosition:kEnvSplitDefaultWidth ofDividerAtIndex:0];
	}

	[self reloadFromStore];
}

- (void)windowDidLoad
{
	[super windowDidLoad];
}

- (void)show
{
	[self ensureWindow];
	[NSApp activateIgnoringOtherApps:YES];
	[self.window center];
	[self showWindow:self];
	[self.window orderFrontRegardless];
	[self.window makeKeyAndOrderFront:self];
	// split / clip 在首屏 layout 完成后再算一次，避免 contentSize 仍为 0 导致 sync 未铺满文档视图
	dispatch_async(dispatch_get_main_queue(), ^{
		[self layoutRightEditorSubviews];
	});
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)self.flatLayers.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= self.flatLayers.count) return nil;
	EnvLayer *l = self.flatLayers[(NSUInteger)row];
	if ([[tableColumn identifier] isEqualToString:@"prio"]) {
		return [NSString stringWithFormat:@"%ld", (long)l.priority];
	}
	NSString *mark = l.enabled ? @"✓ " : @"";
	return [NSString stringWithFormat:@"%@%@", mark, l.name ?: @""];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)obj forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= self.flatLayers.count) return;
	EnvLayer *l = self.flatLayers[(NSUInteger)row];
	NSArray<EnvVarOp *> *ops = [self opsForPersistForLayerId:l.layerId];
	if ([[tableColumn identifier] isEqualToString:@"prio"]) {
		NSInteger p = [obj respondsToSelector:@selector(integerValue)] ? [obj integerValue] : 0;
		EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:l.enabled priority:p ops:ops];
		[self replaceLayerInDocumentWithUpdated:nl];
		return;
	}
	NSString *raw = [obj isKindOfClass:[NSString class]] ? (NSString *)obj : @"";
	raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([raw hasPrefix:@"✓"]) {
		raw = [[raw substringFromIndex:MIN((NSUInteger)1, raw.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
	if ([raw length] == 0) {
		[tableView reloadData];
		return;
	}
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:raw enabled:l.enabled priority:l.priority ops:ops];
	[self replaceLayerInDocumentWithUpdated:nl];
}

- (NSArray<EnvVarOp *> *)opsForPersistForLayerId:(NSString *)lid
{
	if (self.selectedLayer && [self.selectedLayer.layerId isEqualToString:lid] && self.opsTextDirty) {
		return [EnvOpsTextFormat opsFromText:self.opsTextView.string];
	}
	EnvLayer *x = [self layerById:lid];
	return x.ops ?: @[];
}

- (void)replaceLayerInDocumentWithUpdated:(EnvLayer *)nl
{
	NSMutableArray *layers = [self.layers mutableCopy];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		if ([[layers[i] layerId] isEqualToString:nl.layerId]) {
			layers[i] = nl;
			break;
		}
	}
	if (self.selectedLayer && [self.selectedLayer.layerId isEqualToString:nl.layerId]) {
		self.opsTextDirty = NO;
	}
	[self persistLayers:layers];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self commitOpsTextForCurrentLayerIfDirty];
	NSInteger row = self.sourceList.selectedRow;
	if (row < 0 || (NSUInteger)row >= self.flatLayers.count) return;
	[self selectLayer:self.flatLayers[(NSUInteger)row]];
}

#pragma mark - NSSplitViewDelegate（与 EditorController / Editor.xib 中 Gas Mask 主窗口一致）

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	return proposedMinimumPosition + kEnvSplitMinWidth;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	(void)proposedMaximumPosition;
	return kEnvSplitMaxWidth;
}

- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	(void)oldSize;
	NSRect newFrame = [sender frame];
	NSView *left = [sender subviews][0];
	NSRect leftFrame = [left frame];
	NSView *right = [sender subviews][1];
	NSRect rightFrame = [right frame];
	CGFloat dividerThickness = [sender dividerThickness];
	leftFrame.size.height = newFrame.size.height;
	rightFrame.size.width = newFrame.size.width - leftFrame.size.width - dividerThickness;
	rightFrame.size.height = newFrame.size.height;
	rightFrame.origin.x = leftFrame.size.width + dividerThickness;
	[left setFrame:leftFrame];
	[right setFrame:rightFrame];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
	(void)splitView;
	(void)subview;
	return NO;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return @[kEnvTBCreate, kEnvTBRemove, kEnvTBSave, kEnvTBActivate, NSToolbarFlexibleSpaceItemIdentifier, kEnvTBTerminal];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[kEnvTBCreate, kEnvTBRemove, kEnvTBSave, kEnvTBActivate, NSToolbarFlexibleSpaceItemIdentifier, kEnvTBTerminal];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
	[item setTarget:self];
	[item setMinSize:NSMakeSize(28, 28)];
	[item setMaxSize:NSMakeSize(120, 28)];

	if ([itemIdentifier isEqualToString:kEnvTBCreate]) {
		[item setLabel:@"Create"];
		[item setPaletteLabel:@"Create"];
		[item setImage:[NSImage imageNamed:NSImageNameAddTemplate]];
		[item setAction:@selector(createProfile:)];
	} else if ([itemIdentifier isEqualToString:kEnvTBRemove]) {
		[item setLabel:@"Remove"];
		[item setPaletteLabel:@"Remove"];
		[item setImage:[NSImage imageNamed:NSImageNameRemoveTemplate]];
		[item setAction:@selector(removeSelected:)];
	} else if ([itemIdentifier isEqualToString:kEnvTBSave]) {
		[item setLabel:@"Save"];
		[item setPaletteLabel:@"Save"];
		[item setImage:[NSImage imageNamed:NSImageNameBookmarksTemplate]];
		[item setAction:@selector(saveOpsText:)];
	} else if ([itemIdentifier isEqualToString:kEnvTBActivate]) {
		[item setLabel:@"Activate"];
		[item setPaletteLabel:@"Activate"];
		[item setImage:[NSImage imageNamed:NSImageNameMenuOnStateTemplate]];
		[item setAction:@selector(toggleActivateSelected:)];
	} else if ([itemIdentifier isEqualToString:kEnvTBTerminal]) {
		[item setLabel:@"Terminal"];
		[item setPaletteLabel:@"Terminal"];
		[item setImage:[NSImage imageNamed:NSImageNameActionTemplate]];
		[item setAction:@selector(toggleTerminalAutoApply:)];
	}
	return item;
}

#pragma mark - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification
{
	if (notification.object == self.opsTextView) {
		self.opsTextDirty = YES;
		[self syncOpsTextViewGeometryToScrollView];
	}
}

#pragma mark - Actions (toolbar-like)

- (void)createProfile:(id)sender
{
	[self commitOpsTextForCurrentLayerIfDirty];
	NSString *newId = [[NSUUID UUID] UUIDString];
	EnvLayer *nl = [EnvLayer layerWithId:newId name:@"新建Profile" enabled:NO priority:50 ops:@[]];
	NSMutableArray *layers = [self.layers mutableCopy];
	[layers addObject:nl];
	[self persistLayers:layers];
	[self selectLayer:nl];
}

- (void)removeSelected:(id)sender
{
	[self commitOpsTextForCurrentLayerIfDirty];
	if (!self.selectedLayer) return;
	if ([self.selectedLayer.layerId isEqualToString:@"temp"] || [self.selectedLayer.layerId isEqualToString:@"base"]) return;

	NSMutableArray *layers = [NSMutableArray array];
	for (EnvLayer *l in self.layers) {
		if (![l.layerId isEqualToString:self.selectedLayer.layerId]) [layers addObject:l];
	}
	self.selectedLayer = nil;
	[self persistLayers:layers];
}

- (void)toggleActivateSelected:(id)sender
{
	[self commitOpsTextForCurrentLayerIfDirty];
	if (!self.selectedLayer) return;
	EnvLayer *l = self.selectedLayer;
	BOOL en = !l.enabled;
	NSArray<EnvVarOp *> *ops = [self opsForPersistForLayerId:l.layerId];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:en priority:l.priority ops:ops];
	[self replaceLayerInDocumentWithUpdated:nl];
}

- (void)toggleTerminalAutoApply:(id)sender
{
	[self commitOpsTextForCurrentLayerIfDirty];
	// mimic Gas Mask: explicit action button
	NSDictionary *env = [EnvResolver resolveFromLayers:self.layers];
	[EnvExporter writeActiveZshFromEnv:env error:NULL];

	NSError *err = nil;
	if ([EnvExporter isZshrcInstalled]) {
		[EnvExporter uninstallFromZshrc:&err];
	} else {
		[EnvExporter installToZshrc:&err];
	}
}

- (void)refreshPreview:(id)sender
{
	(void)[EnvResolver resolveFromLayers:self.layers];
	NSUInteger n = self.flatLayers.count;
	if (self.statusTextField) {
		[self.statusTextField setStringValue:[NSString stringWithFormat:@"%lu layer(s)", (unsigned long)n]];
	}
	if (@available(macOS 11.0, *)) {
		BOOL on = [EnvExporter isZshrcInstalled];
		self.window.subtitle = on ? @"终端 zsh 已接入" : @"终端 zsh 未接入";
	}
}

@end

