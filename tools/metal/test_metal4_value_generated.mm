#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl4_mechanical_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl4_mechanical_id_count()!=39)return 1;
NSLog(@"metal4 batch190: 39 typed mechanical IDs compiled");return 0;}}
