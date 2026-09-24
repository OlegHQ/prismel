#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl_render_encoder_value_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl_render_encoder_value_id_count()!=14)return 1;
NSLog(@"render/counter batch: 14 direct typed value selectors compiled");return 0;}}
