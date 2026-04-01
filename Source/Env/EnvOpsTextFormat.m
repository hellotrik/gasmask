/***************************************************************************
 * EnvOpsTextFormat — 纯文本行解析，与 hosts 编辑体验一致（无弹窗）。
 ***************************************************************************/

#import "EnvOpsTextFormat.h"
#import "EnvLayer.h"

@implementation EnvOpsTextFormat

+ (NSString *)textFromOps:(NSArray<EnvVarOp *> *)ops
{
	NSMutableString *out = [NSMutableString string];
	[out appendString:@"# EnvMask 变量（每行一条）\n"];
	[out appendString:@"# 覆盖: KEY=VALUE\n"];
	[out appendString:@"# 追加: KEY+=VALUE\n"];
	[out appendString:@"# 删除: -KEY\n"];
	[out appendString:@"#\n"];

	for (EnvVarOp *op in ops) {
		if (!op.key || [op.key length] == 0) continue;
		switch (op.type) {
			case EnvVarOpTypeSet:
				[out appendFormat:@"%@=%@\n", op.key, op.value ?: @""];
				break;
			case EnvVarOpTypeAppendPath:
				[out appendFormat:@"%@+=%@\n", op.key, op.value ?: @""];
				break;
			case EnvVarOpTypeRemove:
				[out appendFormat:@"-%@\n", op.key];
				break;
		}
	}
	return out;
}

+ (NSArray<EnvVarOp *> *)opsFromText:(NSString *)text
{
	if (![text length]) return @[];

	NSMutableArray<EnvVarOp *> *ops = [NSMutableArray array];
	NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

	for (NSString *raw in lines) {
		NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([line length] == 0) continue;
		if ([line hasPrefix:@"#"]) continue;

		if ([line hasPrefix:@"-"] && [line length] > 1) {
			NSString *key = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([key length] == 0) continue;
			[ops addObject:[EnvVarOp removeOpWithKey:key]];
			continue;
		}

		NSRange plusEq = [line rangeOfString:@"+="];
		if (plusEq.location != NSNotFound) {
			NSString *key = [[line substringToIndex:plusEq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSString *val = [[line substringFromIndex:NSMaxRange(plusEq)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([key length] == 0) continue;
			[ops addObject:[EnvVarOp appendPathOpWithKey:key value:val]];
			continue;
		}

		NSRange eq = [line rangeOfString:@"="];
		if (eq.location != NSNotFound) {
			NSString *key = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSString *val = [line substringFromIndex:NSMaxRange(eq)];
			if ([key length] == 0) continue;
			[ops addObject:[EnvVarOp setOpWithKey:key value:val]];
			continue;
		}
	}

	return ops;
}

@end
