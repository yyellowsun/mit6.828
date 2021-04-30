#include <inc/mmu.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

#gdt每个表项都是8byte,第一个表项为null
.set PROT_MODE_CSEG, 0x8         # kernel code segment selector  gdt中的第二个段选择子(第一个为null)，gdt每个表项是8bytes,所以这里是0x8
.set PROT_MODE_DSEG, 0x10        # kernel data segment selector  gdt中的第三个段选择子
.set CR0_PE_ON,      0x1         # protected mode enable flaga   CRO(control register 0）的PE位从0->1 表示protection enable

.globl start
start:
  .code16                     # Assemble for 16-bit mode
  cli                         # Disable interrupts  关闭中断，因为还没有进入保护模式
  cld                         # String operations increment 设置栈增长方向

  # Set up the important data segment registers (DS, ES, SS).
  #将Data,Extra,Stack这些段寄存器全设为0
  xorw    %ax,%ax             # Segment number zero
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # Enable A20:
  #   For backwards compatibility with the earliest PCs, physical
  #   address line 20 is tied low, so that addresses higher than
  #   1MB wrap around to zero by default.  This code undoes this.
  #下面这段代码的意思的是：对物理地址第20位上面的bit进行控制,31-21位保持不变,和保护模式无关
  #打开的话相当于，这一位算出来是多少就写多少，关掉的话，这一位永远为0
  #8042芯片的输出端口P2用于A20 gate
seta20.1:
  inb     $0x64,%al               # Wait for not busy   
  testb   $0x2,%al                # 把64h端口号的1个字节移动到eax寄存器里面
  jnz     seta20.1                # 测试64h端口号位1是否为0，如果为0，则ZF=0，如果为1的话，则ZF=1,一直循环测试
								  #直到64端口号的位1为0，表示8042的输入缓冲区没有数据了。
								  #然后将0xd1写入64h端口号中，表示要向输出端口P2写数据，通过对60h写入0xdf，把P2端口的位1开启A20gate
  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60

  # Switch from real to protected mode, using a bootstrap GDT
  # and segment translation that makes virtual addresses 
  # identical to their physical addresses, so that the 
  # effective memory map does not change during the switch.
  lgdt    gdtdesc            #加载48位的gdt的基地址和界限值（第16位为gdt的界限值，高32位为gdt的基地址)
  movl    %cr0, %eax        #把CR0的PE位置1开启保护模式
  orl     $CR0_PE_ON, %eax
  movl    %eax, %cr0
  
  # Jump to next instruction, but in 32-bit code segment.
  # Switches processor into 32-bit mode.
  ljmp    $PROT_MODE_CSEG, $protcseg    #跳转到.code32的protcseg

  .code32                     # Assemble for 32-bit mode
protcseg:
  # Set up the protected-mode data segment registers
  movw    $PROT_MODE_DSEG, %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS
  movw    %ax, %ss                # -> SS: Stack Segment
  
  # Set up the stack pointer and call into C.
  movl    $start, %esp
  call bootmain

  # If bootmain returns (it shouldn't), loop.
spin:
  jmp spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULL				# null seg
  SEG(STA_X|STA_R, 0x0, 0xffffffff)	# code seg  STA_X,STA_R是type字段，0X0是起始地址，0xffffffff是段界限
  SEG(STA_W, 0x0, 0xffffffff)	        # data seg

gdtdesc:
  .word   0x17                            # sizeof(gdt) - 1
  .long   gdt                             # address gdt

