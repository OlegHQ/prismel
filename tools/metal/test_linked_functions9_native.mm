#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static bool unique_names(NSArray<NSString*>*names){return [NSSet setWithArray:names].count==names.count;}
int main(){@autoreleasepool{
 if(unique_names(@[@"a",@"a"])||!unique_names(@[@"a",@"b"]))return 1;id<MTLDevice>d=MTLCreateSystemDefaultDevice();if(!d)return 77;NSError*error=nil;id<MTLLibrary>library=[d newLibraryWithSource:@"kernel void a(){} kernel void b(){}" options:nil error:&error];if(!library)return 77;id<MTLFunction>a=[library newFunctionWithName:@"a"],b=[library newFunctionWithName:@"b"];if(!a||!b)return 2;
 MTLLinkedFunctions*linked=[MTLLinkedFunctions linkedFunctions];if(!linked)return 3;NSMutableArray*binary_source=[NSMutableArray arrayWithObjects:a,b,nil];NSArray*binary=[binary_source copy],*private_items=[@[b]copy];linked.binaryFunctions=binary;linked.privateFunctions=private_items;linked.groups=[@{@"group_b":@[b],@"group_a":@[a,b]}copy];[binary_source removeAllObjects];if(linked.binaryFunctions.count!=2||linked.privateFunctions.count!=1||linked.groups.count!=2)return 4;if(linked.groups.allKeys.count!=2)return 5;
 __weak id<MTLFunction>weak=a;@autoreleasepool{id<MTLFunction>temporary=a;linked.binaryFunctions=@[temporary];temporary=nil;}if(!weak)return 6;linked.binaryFunctions=nil;linked.privateFunctions=nil;linked.groups=nil;if(linked.binaryFunctions||linked.privateFunctions||linked.groups)return 7;
 if(a.device.registryID!=d.registryID||b.device.registryID!=d.registryID)return 8;return 0;}}
