#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl_io_counter_mechanical_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl_io_counter_mechanical_id_count()!=38)return 1;
NSLog(@"io/counter111: 38 typed mechanical IDs compiled");return 0;}}
