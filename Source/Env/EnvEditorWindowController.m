/***************************************************************************
 * EnvEditorWindowController implementation
 ***************************************************************************/

#import "EnvEditorWindowController.h"

#import "EnvStore.h"
#import "EnvResolver.h"
#import "EnvExporter.h"

@interface EnvEditorWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic) NSSplitView *splitView;
@property (nonatomic) NSTableView *layersTable;
@property (nonatomic) NSTableView *opsTable;
@property (nonatomic) NSTextView *previewText;

@property (nonatomic) NSButton *enabledCheckbox;
@property (nonatomic) NSTextField *priorityField;
@property (nonatomic) NSTextField *layerNameField;

@property (nonatomic) NSArray<EnvLayer *> *layers;
@property (nonatomic) NSInteger selectedLayerIndex;

@end

@implementation EnvEditorWindowController

static EnvEditorWindowController *sharedInstance = nil;

+ (EnvEditorWindowController *)defaultInstance
{
	if (!sharedInstance) {
		sharedInstance = [[EnvEditorWindowController alloc] initWithWindow:nil];
	}
	return sharedInstance;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
	NSButton *btn = [NSButton buttonWithTitle:title target:self action:action];
	[btn setBezelStyle:NSBezelStyleRounded];
	return btn;
}

- (NSTextView *)newReadonlyTextView
{
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[scroll setHasVerticalScroller:YES];
	[scroll setAutohidesScrollers:YES];
	NSTextView *tv = [[NSTextView alloc] initWithFrame:scroll.bounds];
	[tv setEditable:NO];
	[tv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[scroll setDocumentView:tv];
	return tv;
}

- (NSScrollView *)scrollViewWithTable:(NSTableView *)table
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	[sv setHasVerticalScroller:YES];
	[sv setAutohidesScrollers:YES];
	[sv setDocumentView:table];
	return sv;
}

- (NSArray<EnvVarOp *> *)selectedLayerOps
{
	if (self.selectedLayerIndex < 0 || self.selectedLayerIndex >= (NSInteger)[self.layers count]) return @[];
	return self.layers[(NSUInteger)self.selectedLayerIndex].ops ?: @[];
}

- (EnvLayer *)selectedLayer
{
	if (self.selectedLayerIndex < 0 || self.selectedLayerIndex >= (NSInteger)[self.layers count]) return nil;
	return self.layers[(NSUInteger)self.selectedLayerIndex];
}

- (void)reloadDataFromStore
{
	self.layers = [[EnvStore defaultInstance] ensureTempLayerExists];
	if (self.selectedLayerIndex < 0 || self.selectedLayerIndex >= (NSInteger)[self.layers count]) {
		self.selectedLayerIndex = 0;
	}
	[self.layersTable reloadData];
	[self.opsTable reloadData];
	[self refreshSelectedLayerHeaderUI];
	[self refreshPreview:nil];
}

- (void)persistLayers:(NSArray<EnvLayer *> *)layers
{
	[[EnvStore defaultInstance] saveLayers:layers error:NULL];
	self.layers = layers;
	[self.layersTable reloadData];
	[self.opsTable reloadData];
	[self refreshSelectedLayerHeaderUI];
	[self refreshPreview:nil];
}

- (void)refreshSelectedLayerHeaderUI
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;
	[self.enabledCheckbox setState:(l.enabled ? NSOnState : NSOffState)];
	[self.priorityField setStringValue:[NSString stringWithFormat:@"%ld", (long)l.priority]];
	[self.layerNameField setStringValue:(l.name ?: @"")];
}

- (void)ensureWindow
{
	if (self.window) return;

	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 560)
											 styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
											   backing:NSBackingStoreBuffered
												 defer:NO];
	[w setTitle:@"EnvMask 编辑器"];
	[self setWindow:w];

	// SplitView: left layers, right ops + preview
	self.splitView = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
	[self.splitView setVertical:YES];
	[self.splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[w.contentView addSubview:self.splitView];

	// Left: layers table
	self.layersTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 240, 560)];
	NSTableColumn *layerCol = [[NSTableColumn alloc] initWithIdentifier:@"layer"];
	[layerCol setTitle:@"Profiles"];
	[layerCol setWidth:240];
	[self.layersTable addTableColumn:layerCol];
	[self.layersTable setHeaderView:nil];
	[self.layersTable setDelegate:self];
	[self.layersTable setDataSource:self];
	[self.layersTable setAllowsEmptySelection:NO];
	[self.layersTable setAllowsMultipleSelection:NO];

	NSScrollView *layersSv = [self scrollViewWithTable:self.layersTable];
	[layersSv setFrame:NSMakeRect(0, 0, 240, 560)];
	[self.splitView addSubview:layersSv];

	// Right: container view
	NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 560)];
	[right setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

	// Header controls
	self.enabledCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(12, 520, 120, 24)];
	[self.enabledCheckbox setButtonType:NSSwitchButton];
	[self.enabledCheckbox setTitle:@"启用"];
	[self.enabledCheckbox setTarget:self];
	[self.enabledCheckbox setAction:@selector(toggleSelectedLayerEnabled:)];
	[right addSubview:self.enabledCheckbox];

	self.priorityField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 520, 70, 24)];
	[self.priorityField setPlaceholderString:@"prio"];
	[self.priorityField setTarget:self];
	[self.priorityField setAction:@selector(updateSelectedLayerPriority:)];
	[right addSubview:self.priorityField];

	self.layerNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 520, 220, 24)];
	[self.layerNameField setPlaceholderString:@"显示名称"];
	[self.layerNameField setTarget:self];
	[self.layerNameField setAction:@selector(updateSelectedLayerName:)];
	[right addSubview:self.layerNameField];

	NSButton *addOpBtn = [self buttonWithTitle:@"添加变量..." action:@selector(addOpToSelectedLayer:)];
	[addOpBtn setFrame:NSMakeRect(450, 518, 120, 28)];
	[right addSubview:addOpBtn];

	// Ops table
	self.opsTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 580, 360)];
	[self.opsTable setDelegate:self];
	[self.opsTable setDataSource:self];
	[self.opsTable setAllowsMultipleSelection:NO];

	NSTableColumn *keyC = [[NSTableColumn alloc] initWithIdentifier:@"key"];
	[keyC setTitle:@"KEY"];
	[keyC setWidth:200];
	[self.opsTable addTableColumn:keyC];

	NSTableColumn *typeC = [[NSTableColumn alloc] initWithIdentifier:@"type"];
	[typeC setTitle:@"类型"];
	[typeC setWidth:120];
	[self.opsTable addTableColumn:typeC];

	NSTableColumn *valC = [[NSTableColumn alloc] initWithIdentifier:@"value"];
	[valC setTitle:@"VALUE"];
	[valC setWidth:240];
	[self.opsTable addTableColumn:valC];

	NSScrollView *opsSv = [self scrollViewWithTable:self.opsTable];
	[opsSv setFrame:NSMakeRect(12, 190, 556, 320)];
	[opsSv setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[right addSubview:opsSv];

	NSButton *removeOpBtn = [self buttonWithTitle:@"删除选中" action:@selector(removeSelectedOp:)];
	[removeOpBtn setFrame:NSMakeRect(12, 160, 120, 28)];
	[right addSubview:removeOpBtn];

	NSButton *exportBtn = [self buttonWithTitle:@"生成 active.zsh" action:@selector(exportActiveZsh:)];
	[exportBtn setFrame:NSMakeRect(140, 160, 140, 28)];
	[right addSubview:exportBtn];

	NSButton *refreshBtn = [self buttonWithTitle:@"刷新预览" action:@selector(refreshPreview:)];
	[refreshBtn setFrame:NSMakeRect(288, 160, 120, 28)];
	[right addSubview:refreshBtn];

	// Preview
	self.previewText = [self newReadonlyTextView];
	NSScrollView *previewSv = (NSScrollView *)[self.previewText superview];
	[previewSv setFrame:NSMakeRect(12, 12, 556, 140)];
	[previewSv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[right addSubview:previewSv];

	[self.splitView addSubview:right];

	self.selectedLayerIndex = 0;
	[self reloadDataFromStore];
	[self.layersTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (void)show
{
	[self ensureWindow];
	[self.window center];
	[self showWindow:self];
	[self.window makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshPreview:(id)sender
{
	NSArray<EnvLayer *> *layers = self.layers ?: [[EnvStore defaultInstance] loadLayers];
	NSDictionary *env = [EnvResolver resolveFromLayers:layers];

	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"Store: %@\n", [[EnvStore defaultInstance] rootDirectory]];
	[out appendFormat:@"Active script: %@\n\n", [EnvExporter activeZshPath]];
	[out appendString:@"Resolved env:\n"];

	NSArray *keys = [[env allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *k in keys) {
		[out appendFormat:@"%@=%@\n", k, env[k]];
	}

	self.previewText.string = out;
}

- (void)exportActiveZsh:(id)sender
{
	NSArray<EnvLayer *> *layers = self.layers ?: [[EnvStore defaultInstance] loadLayers];
	NSDictionary *env = [EnvResolver resolveFromLayers:layers];
	NSError *err = nil;
	BOOL ok = [EnvExporter writeActiveZshFromEnv:env error:&err];
	if (!ok) {
		NSAlert *a = [NSAlert new];
		[a setMessageText:@"生成 active.zsh 失败"];
		[a setInformativeText:(err.localizedDescription ?: @"未知错误")];
		[a runModal];
	}
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == self.layersTable) {
		return (NSInteger)[self.layers count];
	}
	if (tableView == self.opsTable) {
		return (NSInteger)[[self selectedLayerOps] count];
	}
	return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *identifier = tableColumn.identifier;

	NSTextField *tf = [tableView makeViewWithIdentifier:identifier owner:self];
	if (!tf) {
		tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 20)];
		[tf setBezeled:NO];
		[tf setDrawsBackground:NO];
		[tf setEditable:NO];
		[tf setSelectable:NO];
		tf.identifier = identifier;
	}

	if (tableView == self.layersTable) {
		EnvLayer *l = self.layers[(NSUInteger)row];
		NSString *mark = l.enabled ? @"[x]" : @"[ ]";
		tf.stringValue = [NSString stringWithFormat:@"%@ %@", mark, l.name ?: l.layerId ?: @""];
		return tf;
	}

	if (tableView == self.opsTable) {
		EnvVarOp *op = [self selectedLayerOps][(NSUInteger)row];
		if ([identifier isEqualToString:@"key"]) {
			tf.stringValue = op.key ?: @"";
		} else if ([identifier isEqualToString:@"type"]) {
			switch (op.type) {
				case EnvVarOpTypeSet: tf.stringValue = @"覆盖"; break;
				case EnvVarOpTypeAppendPath: tf.stringValue = @"追加"; break;
				case EnvVarOpTypeRemove: tf.stringValue = @"删除"; break;
			}
		} else if ([identifier isEqualToString:@"value"]) {
			tf.stringValue = op.value ?: @"";
		}
		return tf;
	}

	return tf;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	if (notification.object == self.layersTable) {
		self.selectedLayerIndex = self.layersTable.selectedRow;
		[self.opsTable reloadData];
		[self refreshSelectedLayerHeaderUI];
		[self refreshPreview:nil];
	}
}

#pragma mark - Layer actions

- (void)toggleSelectedLayerEnabled:(id)sender
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;
	if ([l.layerId isEqualToString:@"base"]) {
		[self.enabledCheckbox setState:NSOnState];
		return;
	}

	NSMutableArray<EnvLayer *> *updated = [self.layers mutableCopy];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:(self.enabledCheckbox.state == NSOnState) priority:l.priority ops:l.ops];
	updated[(NSUInteger)self.selectedLayerIndex] = nl;
	[self persistLayers:updated];
}

- (void)updateSelectedLayerPriority:(id)sender
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;
	NSInteger p = [[self.priorityField stringValue] integerValue];
	NSMutableArray<EnvLayer *> *updated = [self.layers mutableCopy];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:l.enabled priority:p ops:l.ops];
	updated[(NSUInteger)self.selectedLayerIndex] = nl;
	[self persistLayers:updated];
}

- (void)updateSelectedLayerName:(id)sender
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;
	NSString *name = [[self.layerNameField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) name = l.layerId;
	NSMutableArray<EnvLayer *> *updated = [self.layers mutableCopy];
	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:name enabled:l.enabled priority:l.priority ops:l.ops];
	updated[(NSUInteger)self.selectedLayerIndex] = nl;
	[self persistLayers:updated];
}

- (void)addOpToSelectedLayer:(id)sender
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;

	NSAlert *alert = [NSAlert new];
	[alert setMessageText:@"添加变量"];
	[alert addButtonWithTitle:@"添加"];
	[alert addButtonWithTitle:@"取消"];

	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 78)];
	NSTextField *keyField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 48, 240, 24)];
	[keyField setPlaceholderString:@"KEY"];
	[accessory addSubview:keyField];

	NSPopUpButton *typePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(250, 48, 170, 24) pullsDown:NO];
	[typePopup addItemWithTitle:@"覆盖 (KEY=VALUE)"];
	[typePopup addItemWithTitle:@"追加 (KEY+=VALUE)"];
	[typePopup addItemWithTitle:@"删除 (unset KEY)"];
	[accessory addSubview:typePopup];

	NSTextField *valField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 12, 420, 24)];
	[valField setPlaceholderString:@"VALUE（删除模式可留空）"];
	[accessory addSubview:valField];

	[alert setAccessoryView:accessory];
	if ([alert runModal] != NSAlertFirstButtonReturn) return;

	NSString *key = [[keyField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *val = [valField stringValue] ?: @"";
	if ([key length] == 0) return;

	EnvVarOpType type = EnvVarOpTypeSet;
	switch ([typePopup indexOfSelectedItem]) {
		case 0: type = EnvVarOpTypeSet; break;
		case 1: type = EnvVarOpTypeAppendPath; break;
		case 2: type = EnvVarOpTypeRemove; break;
	}

	NSMutableArray<EnvVarOp *> *ops = [l.ops mutableCopy] ?: [NSMutableArray array];
	// remove any existing op with same key, then append new one (simple deterministic edit)
	NSMutableArray<EnvVarOp *> *filtered = [NSMutableArray array];
	for (EnvVarOp *op in ops) {
		if (![op.key isEqualToString:key]) [filtered addObject:op];
	}
	EnvVarOp *newOp = nil;
	switch (type) {
		case EnvVarOpTypeSet: newOp = [EnvVarOp setOpWithKey:key value:val]; break;
		case EnvVarOpTypeAppendPath: newOp = [EnvVarOp appendPathOpWithKey:key value:val]; break;
		case EnvVarOpTypeRemove: newOp = [EnvVarOp removeOpWithKey:key]; break;
	}
	if (newOp) [filtered addObject:newOp];

	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:YES priority:l.priority ops:filtered];
	NSMutableArray<EnvLayer *> *updated = [self.layers mutableCopy];
	updated[(NSUInteger)self.selectedLayerIndex] = nl;
	[self persistLayers:updated];
}

- (void)removeSelectedOp:(id)sender
{
	EnvLayer *l = [self selectedLayer];
	if (!l) return;
	NSInteger idx = self.opsTable.selectedRow;
	if (idx < 0 || idx >= (NSInteger)[l.ops count]) return;

	NSMutableArray<EnvVarOp *> *ops = [l.ops mutableCopy];
	[ops removeObjectAtIndex:(NSUInteger)idx];

	EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:l.enabled priority:l.priority ops:ops];
	NSMutableArray<EnvLayer *> *updated = [self.layers mutableCopy];
	updated[(NSUInteger)self.selectedLayerIndex] = nl;
	[self persistLayers:updated];
}

@end

