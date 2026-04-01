/***************************************************************************
 * EnvMaskHostsLikeEditorWindowController implementation
 ***************************************************************************/

#import "EnvMaskHostsLikeEditorWindowController.h"

#import "EnvStore.h"
#import "EnvResolver.h"
#import "EnvExporter.h"
#import "EnvTreeItem.h"
#import "EnvOpsTextFormat.h"

@interface EnvMaskHostsLikeEditorWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic) NSSplitView *splitView;

@property (nonatomic) NSOutlineView *sourceList;
@property (nonatomic) EnvTreeItem *rootItem;

@property (nonatomic) NSTextView *opsTextView;
@property (nonatomic) NSTextView *previewText;

@property (nonatomic) NSButton *enabledCheckbox;
@property (nonatomic) NSTextField *priorityField;
@property (nonatomic) NSTextField *nameField;

@property (nonatomic) NSView *rightEditorView;
@property (nonatomic) NSScrollView *opsScrollView;
@property (nonatomic) NSScrollView *previewScrollView;
@property (nonatomic) NSButton *createBtn;
@property (nonatomic) NSButton *removeBtn;
@property (nonatomic) NSButton *enableBtn;
@property (nonatomic) NSButton *applyBtn;
@property (nonatomic) NSButton *saveOpsBtn;

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

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
	NSButton *btn = [NSButton buttonWithTitle:title target:self action:action];
	[btn setBezelStyle:NSBezelStyleRounded];
	return btn;
}

- (NSScrollView *)scrollViewWithView:(NSView *)view
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[sv setHasVerticalScroller:YES];
	[sv setAutohidesScrollers:YES];
	[sv setDocumentView:view];
	return sv;
}

- (NSTextView *)newReadonlyTextView
{
	NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[tv setEditable:NO];
	[tv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	return tv;
}

/// 预览固定高度贴底，变量编辑区填满中间，避免两者同时 HeightSizable 导致重叠、预览盖住 ops 无法点击输入。
- (void)layoutRightEditorSubviews
{
	NSView *right = self.rightEditorView;
	if (!right) return;

	const CGFloat margin = 12.0;
	const CGFloat previewHDefault = 160.0;
	const CGFloat gapPO = 8.0;
	const CGFloat gapOH = 8.0;
	const CGFloat gapHT = 12.0;
	const CGFloat toolbarH = 28.0;
	const CGFloat headerH = 24.0;
	const CGFloat topMargin = 8.0;
	const CGFloat minOpsH = 80.0;
	const CGFloat minPreviewH = 80.0;

	CGFloat W = NSWidth(right.bounds);
	CGFloat H = NSHeight(right.bounds);
	CGFloat innerW = MAX(0.0, W - 2.0 * margin);

	CGFloat topBlock = topMargin + toolbarH + gapHT + headerH + gapOH;
	CGFloat previewH = previewHDefault;
	CGFloat bottomBlock = margin + previewH + gapPO;
	CGFloat opsH = H - topBlock - bottomBlock;
	if (opsH < minOpsH) {
		CGFloat shortfall = minOpsH - opsH;
		previewH = MAX(minPreviewH, previewH - shortfall);
		bottomBlock = margin + previewH + gapPO;
		opsH = H - topBlock - bottomBlock;
	}

	CGFloat toolbarBottomY = H - topMargin - toolbarH;
	CGFloat headerTopY = toolbarBottomY - gapHT;
	CGFloat headerBottomY = headerTopY - headerH;
	CGFloat opsBottomY = margin + previewH + gapPO;

	[self.createBtn setFrame:NSMakeRect(margin, toolbarBottomY, 110, toolbarH)];
	[self.removeBtn setFrame:NSMakeRect(128, toolbarBottomY, 110, toolbarH)];
	[self.enableBtn setFrame:NSMakeRect(244, toolbarBottomY, 140, toolbarH)];
	[self.applyBtn setFrame:NSMakeRect(390, toolbarBottomY, 160, toolbarH)];
	[self.saveOpsBtn setFrame:NSMakeRect(556, toolbarBottomY, 100, toolbarH)];

	[self.enabledCheckbox setFrame:NSMakeRect(12, headerBottomY, 90, headerH)];
	[self.priorityField setFrame:NSMakeRect(110, headerBottomY, 70, headerH)];
	[self.nameField setFrame:NSMakeRect(190, headerBottomY, MAX(80.0, W - margin - 190.0), headerH)];

	[self.previewScrollView setFrame:NSMakeRect(margin, margin, innerW, previewH)];
	[self.opsScrollView setFrame:NSMakeRect(margin, opsBottomY, innerW, opsH)];
	[self syncOpsTextViewGeometryToScrollView];
}

/// 将 ops 文档视图铺满可视区（至少与 clip 同高），否则下方空白不属于 NSTextView，点击无法成为第一响应者、无法输入（含中文 IME）。
- (void)syncOpsTextViewGeometryToScrollView
{
	NSScrollView *sv = self.opsScrollView;
	NSTextView *tv = self.opsTextView;
	if (!sv || !tv) return;

	NSSize contentSize = sv.contentSize;
	if (contentSize.width < 1.0 || contentSize.height < 1.0) return;

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
	NSInteger p = [self.priorityField.stringValue integerValue];
	NSString *name = [[self.nameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) name = l.name ?: @"";
	BOOL en = (self.enabledCheckbox.state == NSOnState);
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

- (EnvTreeItem *)buildTreeFromLayers:(NSArray<EnvLayer *> *)layers
{
	NSMutableArray<EnvTreeItem *> *profileLeaves = [NSMutableArray array];
	EnvLayer *tempLayer = nil;

	NSArray<EnvLayer *> *sorted = [layers sortedArrayUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		return [a.name compare:b.name options:NSCaseInsensitiveSearch];
	}];

	for (EnvLayer *l in sorted) {
		if ([l.layerId isEqualToString:@"temp"]) {
			tempLayer = l;
			continue;
		}
		// Hide base from source list (internal), but keep it for resolution.
		if ([l.layerId isEqualToString:@"base"]) {
			continue;
		}
		[profileLeaves addObject:[EnvTreeItem leafWithLayer:l]];
	}

	EnvTreeItem *profiles = [EnvTreeItem groupWithTitle:@"Profiles" children:profileLeaves];
	EnvTreeItem *temp = nil;
	if (tempLayer) {
		temp = [EnvTreeItem groupWithTitle:@"Temp" children:@[[EnvTreeItem leafWithLayer:tempLayer]]];
	} else {
		temp = [EnvTreeItem groupWithTitle:@"Temp" children:@[]];
	}

	return [EnvTreeItem groupWithTitle:@"ROOT" children:@[profiles, temp]];
}

- (void)reloadFromStore
{
	self.layers = [[EnvStore defaultInstance] ensureTempLayerExists];
	self.rootItem = [self buildTreeFromLayers:self.layers];
	[self.sourceList reloadData];

	// select first profile if nothing selected
	if (!self.selectedLayer) {
		EnvTreeItem *profiles = self.rootItem.children.firstObject;
		EnvTreeItem *firstLeaf = profiles.children.firstObject;
		if (firstLeaf.layer) {
			[self selectLayer:firstLeaf.layer];
		}
	}

	[self refreshPreview:nil];
}

- (void)selectLayer:(EnvLayer *)layer
{
	self.selectedLayer = layer;
	[self.enabledCheckbox setState:(layer.enabled ? NSOnState : NSOffState)];
	[self.priorityField setStringValue:[NSString stringWithFormat:@"%ld", (long)layer.priority]];
	[self.nameField setStringValue:(layer.name ?: @"")];
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
	[[EnvStore defaultInstance] saveLayers:layers error:NULL];
	self.layers = layers;
	self.rootItem = [self buildTreeFromLayers:layers];
	[self.sourceList reloadData];

	if (self.selectedLayer) {
		EnvLayer *updatedSelected = [self layerById:self.selectedLayer.layerId];
		if (updatedSelected) {
			[self selectLayer:updatedSelected];
		}
	}
	[self refreshPreview:nil];
}

#pragma mark - Window

- (void)ensureWindow
{
	if (self.window) return;

	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 980, 620)
											 styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
											   backing:NSBackingStoreBuffered
												 defer:NO];
	[w setTitle:@"EnvMask（仿 Gas Mask）"];
	[self setWindow:w];

	self.splitView = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
	[self.splitView setVertical:YES];
	[self.splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[w.contentView addSubview:self.splitView];

	// Left: SourceList outline
	self.sourceList = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 240, 620)];
	NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[col setTitle:@"Env"];
	[col setWidth:240];
	[self.sourceList addTableColumn:col];
	[self.sourceList setOutlineTableColumn:col];
	[self.sourceList setHeaderView:nil];
	[self.sourceList setRowHeight:20.0];
	[self.sourceList setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
	[self.sourceList setDelegate:self];
	[self.sourceList setDataSource:self];

	NSScrollView *leftSv = [self scrollViewWithView:self.sourceList];
	[leftSv setFrame:NSMakeRect(0, 0, 240, 620)];
	[self.splitView addSubview:leftSv];

	// Right: editor（子视图由 layoutRightEditorSubviews 布局，避免预览与 ops 重叠抢点击）
	NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 740, 620)];
	[right setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	self.rightEditorView = right;
	[right setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layoutRightEditorSubviews) name:NSViewFrameDidChangeNotification object:right];

	// Toolbar-like buttons row
	self.createBtn = [self buttonWithTitle:@"Create(+)" action:@selector(createProfile:)];
	[right addSubview:self.createBtn];

	self.removeBtn = [self buttonWithTitle:@"Remove" action:@selector(removeSelected:)];
	[right addSubview:self.removeBtn];

	self.enableBtn = [self buttonWithTitle:@"Enable/Disable" action:@selector(toggleEnableSelected:)];
	[right addSubview:self.enableBtn];

	self.applyBtn = [self buttonWithTitle:@"ApplyToTerminal" action:@selector(toggleTerminalAutoApply:)];
	[right addSubview:self.applyBtn];

	self.saveOpsBtn = [self buttonWithTitle:@"保存编辑" action:@selector(saveOpsText:)];
	[right addSubview:self.saveOpsBtn];

	// Header fields
	self.enabledCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(12, 548, 90, 24)];
	[self.enabledCheckbox setButtonType:NSSwitchButton];
	[self.enabledCheckbox setTitle:@"启用"];
	[self.enabledCheckbox setTarget:self];
	[self.enabledCheckbox setAction:@selector(setSelectedEnabledFromCheckbox:)];
	[right addSubview:self.enabledCheckbox];

	self.priorityField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 548, 70, 24)];
	[self.priorityField setPlaceholderString:@"prio"];
	[self.priorityField setEditable:YES];
	[self.priorityField setSelectable:YES];
	[self.priorityField setEnabled:YES];
	self.priorityField.delegate = self;
	[self.priorityField setTarget:self];
	[self.priorityField setAction:@selector(updateSelectedPriority:)];
	[right addSubview:self.priorityField];

	self.nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 548, 260, 24)];
	[self.nameField setPlaceholderString:@"显示名称"];
	[self.nameField setEditable:YES];
	[self.nameField setSelectable:YES];
	[self.nameField setEnabled:YES];
	self.nameField.delegate = self;
	[self.nameField setTarget:self];
	[self.nameField setAction:@selector(updateSelectedName:)];
	[right addSubview:self.nameField];

	// Preview 先加、变量编辑后加，保证 ops 在上层（即使曾重叠也能点到）
	self.previewText = [self newReadonlyTextView];
	self.previewScrollView = [self scrollViewWithView:self.previewText];
	[self.previewScrollView setBorderType:NSBezelBorder];
	[right addSubview:self.previewScrollView];

	self.opsTextView = [self newEditableOpsTextView];
	self.opsScrollView = [self scrollViewWithView:self.opsTextView];
	[self.opsScrollView setBorderType:NSBezelBorder];
	[right addSubview:self.opsScrollView];

	[self.splitView addSubview:right];

	[self layoutRightEditorSubviews];

	[self reloadFromStore];
	[self.sourceList expandItem:nil expandChildren:YES];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj
{
	// Do NOT persist on every keystroke. Persist triggers reload+reselect which steals focus
	// and makes the text field feel "unable to type".
	id field = obj.object;
	if (field == self.nameField) {
		[self updateSelectedName:self.nameField];
	} else if (field == self.priorityField) {
		[self updateSelectedPriority:self.priorityField];
	}
}

- (void)show
{
	[self ensureWindow];
	[NSApp activateIgnoringOtherApps:YES];
	[self.window center];
	[self showWindow:self];
	[self.window orderFrontRegardless];
	[self.window makeKeyAndOrderFront:self];
}

#pragma mark - Outline datasource

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	EnvTreeItem *i = item ?: self.rootItem;
	return i.children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [(EnvTreeItem *)item isGroup];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	EnvTreeItem *i = item ?: self.rootItem;
	return (NSInteger)[i.children count];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	EnvTreeItem *i = (EnvTreeItem *)item;
	if (i.isGroup) return i.title;
	EnvLayer *l = i.layer;
	NSString *mark = l.enabled ? @"✓" : @"";
	return [NSString stringWithFormat:@"%@ %@", mark, i.title ?: @""];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return [(EnvTreeItem *)item selectable];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self commitOpsTextForCurrentLayerIfDirty];

	EnvTreeItem *i = [self.sourceList itemAtRow:self.sourceList.selectedRow];
	if (!i || i.isGroup) return;
	if (i.layer) [self selectLayer:i.layer];
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

- (void)toggleEnableSelected:(id)sender
{
	[self commitOpsTextForCurrentLayerIfDirty];
	if (!self.selectedLayer) return;
	BOOL newEnabled = !self.selectedLayer.enabled;
	[self.enabledCheckbox setState:(newEnabled ? NSOnState : NSOffState)];
	[self setSelectedEnabledFromCheckbox:nil];
}

- (void)setSelectedEnabledFromCheckbox:(id)sender
{
	if (!self.selectedLayer) return;
	EnvLayer *l = self.selectedLayer;
	BOOL enabled = (self.enabledCheckbox.state == NSOnState);
	NSArray<EnvVarOp *> *ops = [self resolvedOpsForPersist];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:enabled priority:l.priority ops:ops];

	NSMutableArray *layers = [self.layers mutableCopy];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		EnvLayer *x = layers[i];
		if ([x.layerId isEqualToString:l.layerId]) { layers[i] = nl; break; }
	}
	self.opsTextDirty = NO;
	[self persistLayers:layers];
}

- (void)updateSelectedPriority:(id)sender
{
	if (!self.selectedLayer) return;
	EnvLayer *l = self.selectedLayer;
	NSInteger p = [self.priorityField.stringValue integerValue];
	NSArray<EnvVarOp *> *ops = [self resolvedOpsForPersist];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:l.enabled priority:p ops:ops];

	NSMutableArray *layers = [self.layers mutableCopy];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		EnvLayer *x = layers[i];
		if ([x.layerId isEqualToString:l.layerId]) { layers[i] = nl; break; }
	}
	self.opsTextDirty = NO;
	[self persistLayers:layers];
}

- (void)updateSelectedName:(id)sender
{
	if (!self.selectedLayer) return;
	EnvLayer *l = self.selectedLayer;
	NSString *name = [self.nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) return;
	NSArray<EnvVarOp *> *ops = [self resolvedOpsForPersist];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:name enabled:l.enabled priority:l.priority ops:ops];

	NSMutableArray *layers = [self.layers mutableCopy];
	for (NSUInteger i = 0; i < [layers count]; i++) {
		EnvLayer *x = layers[i];
		if ([x.layerId isEqualToString:l.layerId]) { layers[i] = nl; break; }
	}
	self.opsTextDirty = NO;
	[self persistLayers:layers];
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
	NSDictionary *env = [EnvResolver resolveFromLayers:self.layers];
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"终端自动生效: %@\n", ([EnvExporter isZshrcInstalled] ? @"已开启" : @"未开启")];
	[out appendFormat:@"Store: %@\n", [[EnvStore defaultInstance] rootDirectory]];
	[out appendFormat:@"导出脚本: %@\n\n", [EnvExporter activeZshPath]];
	[out appendString:@"Resolved env:\n"];
	NSArray *keys = [[env allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *k in keys) {
		[out appendFormat:@"%@=%@\n", k, env[k]];
	}
	self.previewText.string = out;
}

@end

