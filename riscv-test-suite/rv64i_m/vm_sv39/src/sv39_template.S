#include "model_test.h"

#include "arch_test.h"

RVTEST_ISA("RV64I_Zicsr")

# Test code region
.section .text.init
.globl rvtest_entry_point
rvtest_entry_point:
RVMODEL_BOOT
RVTEST_CODE_BEGIN

# ---------------------------------------------------------------------------------------------
// Test the RWX permissions
.macro VERIFICATION_RWX ADDRESS, level	
   	LA(a5, \ADDRESS)														// Fetch the address to be checked
	addi a2, a2, 16															// 16 stored in a2 for starting point

	// Check store on the address.
	sw	a2, 20(a5)
	SREG a2, 0(s11)
	nop
	addi s11, s11, REGWIDTH

	lw	a4, 20(a5)															// Reload for verification (CHECK IF DATA HAS BEEN UPDATED SUCCESSFULLY)
	SREG a4, 0(s11)
	nop
	addi s11, s11, REGWIDTH

	//check if level is equal to zero, if it is then jump to the end of the 4KB to check the permissions
	//else jump to the end of the 4MB page to check the permissions
    // Check if level is equal to zero (4KB page)
	addi a2, a2, 16															// update the counter for execute
    LI( t1, \level)
    beqz t1, 1f  // Forward reference to avoid label redefinition
    
    // 4MB - 4 = 4,194,300 bytes
	// Access the last four bytes which contain the jr instruction
    LI (t0, (0x400000 - 4))
    srli a5, a5, 22
    slli a5, a5, 22															//Clear the lower 21 bits -- offset bits(10) + level 0 bits(12)
    add t0, a5, t0
    jalr ra, t0, 0
	SREG a2, 0(s11)
	nop
	addi s11, s11, REGWIDTH
    j 2f
    
1:  // 4KB - 4 = 4,092 bytes
    LI (t0, (0x1000-4))
    srli a5, a5, 12
    slli a5, a5, 12
    add t0, a5, t0
    jalr ra, t0, 0
	SREG a2, 0(s11)
	nop
	addi s11, s11, REGWIDTH

2:  // end_macro
    // execution test sig update
	nop
.endm

.macro TEST_CASES_RUNNER LOWER_MODE, VA, level
	RVTEST_GOTO_LOWER_MODE	\LOWER_MODE		                                // Switching to S mode
	.align 2

	//JUMP TO LOAD, STORE, EXECUTE CHECK MACRO (SEE ON TOP)
	VERIFICATION_RWX	\VA, \level
	nop
	nop

	RVTEST_GOTO_MMODE		                                        		// Switching back to M mode

.endm

main:
#ifdef rvtest_mtrap_routine					                				// Verification of existance of rvtest_mtrap_routine
	LI a4, 0xceed
	RVTEST_SIGUPD(x13,a4)
#endif
#ifdef rvtest_strap_routine					                				// Verification of existance of rvtest_strap_routine
	LI a4, 0xbeed
	RVTEST_SIGUPD(x13,a4)
#endif
	
	ALL_MEM_PMP          		                  	                      	// set the PMP permissions for the whole memory
	csrw satp, zero  		                                        		// write satp with all zeros (bare mode)

//---------------------------------------------------------------------------------------------------------------------------------
//								Virtual addresses definition section for the code, data, sig, vmem, test sections
//---------------------------------------------------------------------------------------------------------------------------------
	// test section VAs
	.set va_data,          		0xffffffc300000000                   // virtual address of rvtest_data_1_l2, rvtest_data_1_l1 and rvtest_data_1_l0
	.set va_return_page_l2,     0xffffffc340000000                   // virtual address of return_page for the rvtest_data_1_l2
	.set va_return_page_l1,     0xffffffc300200000                   // virtual address of return_page for the rvtest_data_1_l1
	.set va_return_page_l0,     0xffffffc300001000					 // virtual address of return_page for the rvtest_data_1_l0


//---------------------------------------------------------------------------------------------------------------------------------
//												Test Cases Start from here
//---------------------------------------------------------------------------------------------------------------------------------

	SATP_SETUP_RV64(sv39)                                                   // set the SATP for virtualization
	sfence.vma                                                              // flush the TLB

//---------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------
//													TESTS AT LEVEL 2
//---------------------------------------------------------------------------------------------------------------------------------
//					4MB PAGE	Region 1 under test at level 2 -- RWX permissions given to the region
//---------------------------------------------------------------------------------------------------------------------------------
	// Test case 2: Test in S-Mode | RSW set to 1 | expected = successful page access with no affect on these bits
	PTE_SETUP_RV64(rvtest_data_1_l1, (PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V | (1 << 8)), t0, t1, va_data, LEVEL2, sv39)
	sfence.vma

	//return page PTE
	PTE_SETUP_RV64(rvtest_data_1_l1, (PTE_D | PTE_A | PTE_R | PTE_W | PTE_X | PTE_V), t0, t1, va_return_page_l1, LEVEL2, sv39)
	sfence.vma

	TEST_CASES_RUNNER Smode, va_data, LEVEL2



#endif
//---------------------------------------------------------------------------------------------------------------------------------
RVTEST_CODE_END
RVMODEL_HALT
RVTEST_DATA_BEGIN
.align 30

//---------------------------------------------------------------------------------------------------------------------------------
//											PHYSICAL ADDRESS REGIONS FOR TESTING
//---------------------------------------------------------------------------------------------------------------------------------
//Physical Address region under testing for LEVEL 2
rvtest_data_1_l2:
	nop																		//nops are added so if there is a trap
	addi ra, ra, REGWIDTH
	jr ra																	// return back if the access fault
	nop
	.word 0xbeefcaf1														// Random word
	.word 0xbeefcaf2														// Random word
	.rept ((1 << 28) - 7)													// (2^30 - 7) nops
    nop
	.endr
	jr ra	

//Physical Address region under testing for LEVEL 1
rvtest_data_1_l1:
	nop																		//nops are added so if there is a trap
	addi ra, ra, REGWIDTH
	jr ra																	// return back if the access fault
	nop
	.word 0xbeefcaf1														// Random word
	.word 0xbeefcaf2														// Random word
	.rept ((1 << 19) - 7)													// (2^21 - 7) nops
    nop
	.endr
	jr ra																	// return back if successful access

//Physical Address region under testing for LEVEL 0
rvtest_data_1_l0:
	nop																		// trap return back skip
	addi ra, ra, REGWIDTH
	jr ra																	//jump back for the trap on level 1
	nop
	.word 0xbeefcaf1														// Random word
	.word 0xbeefcaf2														// Random word
	.rept ((1 << 10) - 7)													// (2^12 - 7) nops
    nop
	.endr
	jr ra

//---------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------------------------------------------------------------------------------------------

#ifdef rvtest_strap_routine
.align 12
rvtest_slvl1_pg_tbl:
		RVTEST_PTE_IDENT_MAP(0, 1 ,PTE_V | PTE_A | PTE_D | PTE_G)
#endif

RVTEST_DATA_END                               
.align 12
RVMODEL_DATA_BEGIN
rvtest_sig_begin:
sig_begin_canary:
CANARY;

// test signatures initialization
signature_x13_1:
    .fill 128*(XLEN/32),4,0xcafebeef

// trap signatures initialization
#ifdef rvtest_mtrap_routine
mtrap_sigptr:
    .fill 128*(XLEN/32),4,0xdeadbeef
#endif

sig_end_canary:
CANARY;
rvtest_sig_end:
RVMODEL_DATA_END
