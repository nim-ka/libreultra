# Modified SM64 makefile

### Default target ###

default: libultra

### Build Options ###
# Version of the game to build and graphics microcode used
VERSION ?= us

# If ENDIAN_IND is 1, enable non-matching code changes that try to ensure
# endianness independence
ENDIAN_IND ?= 0

# Release

ifeq ($(VERSION),jp)
  VERSION_CFLAGS := -DVERSION_JP=1
  VERSION_ASFLAGS := --defsym VERSION_JP=1
else
ifeq ($(VERSION),us)
  VERSION_CFLAGS := -DVERSION_US=1
  VERSION_ASFLAGS := --defsym VERSION_US=1
else
  $(error unknown version "$(VERSION)")
endif
endif

ifeq ($(ENDIAN_IND),1)
  VERSION_CFLAGS := $(VERSION_CFLAGS) -DENDIAN_IND=1
  COMPARE := 0
endif

################ Target Executable and Sources ###############

# BUILD_DIR is location where all build artifacts are placed
BUILD_DIR_BASE := build
BUILD_DIR := $(BUILD_DIR_BASE)/$(VERSION)

LIBULTRA := $(BUILD_DIR)/libultra.a
ROM := $(BUILD_DIR)/$(TARGET).z64
ELF := $(BUILD_DIR)/$(TARGET).elf
LD_SCRIPT := sm64.ld
MIO0_DIR := $(BUILD_DIR)/mio0
TEXTURE_DIR := textures
ACTOR_DIR := actors

# Directories containing source files
# SRC_DIRS := src src/engine src/game src/goddard src/goddard/dynlists src/audio
ASM_DIRS := asm actors lib data levels assets text
BIN_DIRS := bin

ULTRA_SRC_DIRS := lib/src lib/src/math
ULTRA_ASM_DIRS := lib/asm lib/data
ULTRA_BIN_DIRS := lib/bin

LEVEL_DIRS := $(patsubst levels/%,%,$(dir $(wildcard levels/*/header.s)))

MIPSISET := -mips2 -32
OPT_FLAGS := -O2

# Source code files
C_FILES := $(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.c))
S_FILES := $(foreach dir,$(ASM_DIRS),$(wildcard $(dir)/*.s))
ULTRA_C_FILES := $(foreach dir,$(ULTRA_SRC_DIRS),$(wildcard $(dir)/*.c))
ULTRA_S_FILES := $(foreach dir,$(ULTRA_ASM_DIRS),$(wildcard $(dir)/*.s))
LEVEL_S_FILES := $(addsuffix header.s,$(addprefix bin/,$(LEVEL_DIRS)))
SEG_IN_FILES := $(foreach dir,$(BIN_DIRS),$(wildcard $(dir)/*.s.in))
SEG_S_FILES := $(foreach dir,$(BIN_DIRS),$(wildcard $(dir)/*.s)) \
               $(foreach file,$(SEG_IN_FILES),$(file:.s.in=.s))

# Object files
O_FILES := $(foreach file,$(C_FILES),$(BUILD_DIR)/$(file:.c=.o)) \
           $(foreach file,$(S_FILES),$(BUILD_DIR)/$(file:.s=.o)) \
           $(foreach file,$(LEVEL_S_FILES),$(BUILD_DIR)/$(file:.s=.o))

ULTRA_O_FILES := $(foreach file,$(ULTRA_S_FILES),$(BUILD_DIR)/$(file:.s=.o)) \
                 $(foreach file,$(ULTRA_C_FILES),$(BUILD_DIR)/$(file:.c=.o))

# Automatic dependency files
DEP_FILES := $(O_FILES:.o=.d) $(ULTRA_O_FILES:.o=.d)

# Files with NON_MATCHING ifdefs
NON_MATCHING_C_FILES != grep -rl NON_MATCHING $(wildcard src/audio/*.c)
NON_MATCHING_O_FILES = $(foreach file,$(NON_MATCHING_C_FILES),$(BUILD_DIR)/$(file:.c=.o))
NON_MATCHING_DEP = $(BUILD_DIR)/src/audio/non_matching_dep

# Segment elf files
SEG_FILES := $(foreach file,$(SEG_S_FILES),$(BUILD_DIR)/$(file:.s=.elf)) $(ACTOR_ELF_FILES) $(LEVEL_ELF_FILES)

##################### Compiler Options #######################
IRIX_ROOT := tools/ido5.3_compiler

ifeq ($(shell type mips-linux-gnu-ld >/dev/null 2>/dev/null; echo $$?), 0)
  CROSS := mips-linux-gnu-
else
  CROSS := mips64-elf-
endif

AS        := $(CROSS)as
CC        := ./qemu-irix -silent -L $(IRIX_ROOT) $(IRIX_ROOT)/usr/bin/cc # Original compiler
CPP       := cpp -P
LD        := $(CROSS)ld
AR        := $(CROSS)ar
OBJDUMP   := $(CROSS)objdump
OBJCOPY   := $(CROSS)objcopy

# Check code syntax with host compiler
CC_CHECK := gcc -fsyntax-only -fsigned-char -nostdinc -I include -I $(BUILD_DIR)/include -I src -std=gnu90 -Wall -Wextra -Wno-format-security -D_LANGUAGE_C $(VERSION_CFLAGS) $(GRUCODE_CFLAGS)

ASFLAGS := -march=vr4300 -mabi=32 -I include -I $(BUILD_DIR) $(VERSION_ASFLAGS) $(GRUCODE_ASFLAGS)
CFLAGS = -Wab,-r4300_mul -non_shared -G 0 -Xcpluscomm -Xfullwarn $(OPT_FLAGS) -signed -I include -I $(BUILD_DIR)/include -I src -D_LANGUAGE_C $(VERSION_CFLAGS) $(MIPSISET) $(GRUCODE_CFLAGS)
OBJCOPYFLAGS := --pad-to=0x800000 --gap-fill=0xFF
SYMBOL_LINKING_FLAGS := $(addprefix -R ,$(SEG_FILES))
LDFLAGS := -T undefined_syms.txt -T $(BUILD_DIR)/$(LD_SCRIPT) -Map $(BUILD_DIR)/sm64.map --no-check-sections $(SYMBOL_LINKING_FLAGS)

ifeq ($(shell getconf LONG_BIT), 32)
  # Work around memory allocation bug in QEMU
  export QEMU_GUEST_BASE := 1
else
  # Ensure that gcc treats the code as 32-bit
  CC_CHECK += -m32
endif

####################### Other Tools #########################

# N64 tools
TOOLS_DIR = tools

# Make tools if out of date
DUMMY != make -s -C tools >&2

###################### Dependency Check #####################

BINUTILS_VER_MAJOR := $(shell $(LD) --version | grep ^GNU | sed 's/^.* //; s/\..*//g')
BINUTILS_VER_MINOR := $(shell $(LD) --version | grep ^GNU | sed 's/^[^.]*\.//; s/\..*//g')
BINUTILS_DEPEND := $(shell expr $(BINUTILS_VER_MAJOR) \>= 2 \& $(BINUTILS_VER_MINOR) \>= 27)
ifeq ($(BINUTILS_DEPEND),0)
$(error binutils version 2.27 required, version $(BINUTILS_VER_MAJOR).$(BINUTILS_VER_MINOR) detected)
endif

ifndef QEMU_IRIX
$(error env variable QEMU_IRIX should point to the qemu-mips binary)
endif

######################## Targets #############################

all: $(ROM)
ifeq ($(COMPARE),1)
	@$(SHA1SUM) -c $(TARGET).sha1
endif

clean:
	$(RM) -r $(BUILD_DIR_BASE)

libultra: $(BUILD_DIR)/libultra.a

$(BUILD_DIR)/lib/bin/ipl3_font.bin: lib/ipl3_font.png | $(BUILD_DIR)
	$(IPLFONTUTIL) e $< $@

ALL_DIRS := $(BUILD_DIR) $(addprefix $(BUILD_DIR)/,$(SRC_DIRS) $(ASM_DIRS) $(ULTRA_SRC_DIRS) $(ULTRA_ASM_DIRS) $(ULTRA_BIN_DIRS) $(BIN_DIRS) $(TEXTURE_DIRS) $(addprefix levels/,$(LEVEL_DIRS)) $(addprefix bin/,$(LEVEL_DIRS)) include) $(MIO0_DIR) $(addprefix $(MIO0_DIR)/,$(LEVEL_DIRS))

# Make sure build directory exists before compiling anything
DUMMY != mkdir -p $(ALL_DIRS)

# Source code
$(BUILD_DIR)/lib/src/%.o: OPT_FLAGS :=
$(BUILD_DIR)/lib/src/math/ll%.o: MIPSISET := -mips3 -32
$(BUILD_DIR)/lib/src/math/%.o: OPT_FLAGS := -O2
$(BUILD_DIR)/lib/src/math/ll%.o: OPT_FLAGS :=
$(BUILD_DIR)/lib/src/ldiv.o: OPT_FLAGS := -O2
$(BUILD_DIR)/lib/src/string.o: OPT_FLAGS := -O2
# $(BUILD_DIR)/lib/src/gu%.o: OPT_FLAGS := -O3
# $(BUILD_DIR)/lib/src/al%.o: OPT_FLAGS := -O3

# Rebuild files with '#ifdef NON_MATCHING' when that macro changes.
$(NON_MATCHING_O_FILES): $(NON_MATCHING_DEP).$(NON_MATCHING)
$(NON_MATCHING_DEP).$(NON_MATCHING):
	@rm -f $(NON_MATCHING_DEP).*
	touch $@

$(BUILD_DIR)/lib/src/math/%.o: lib/src/math/%.c
	@$(CC_CHECK) -MMD -MP -MT $@ -MF $(BUILD_DIR)/lib/src/math/$*.d $<
	$(CC) -c $(CFLAGS) -o $@ $<
	tools/patch_libultra_math $@ || rm $@

$(BUILD_DIR)/%.o: %.c
	@$(CC_CHECK) -MMD -MP -MT $@ -MF $(BUILD_DIR)/$*.d $<
	$(CC) -c $(CFLAGS) -o $@ $<


$(BUILD_DIR)/%.o: %.s $(MIO0_FILES)
	$(AS) $(ASFLAGS) -MD $(BUILD_DIR)/$*.d -o $@ $<

$(BUILD_DIR)/$(LD_SCRIPT): $(LD_SCRIPT)
	$(CPP) $(VERSION_CFLAGS) -I include/ -DBUILD_DIR=$(BUILD_DIR) -o $@ $<

$(BUILD_DIR)/libultra.a: $(ULTRA_O_FILES)
	$(AR) rcs -o $@ $(ULTRA_O_FILES)

$(ELF): $(O_FILES) $(MIO0_OBJ_FILES) $(SEG_FILES) $(BUILD_DIR)/$(LD_SCRIPT) undefined_syms.txt $(BUILD_DIR)/libultra.a
	$(LD) -L $(BUILD_DIR) $(LDFLAGS) -o $@ $(O_FILES)$(LIBS) -lultra

$(ROM): $(ELF)
	$(OBJCOPY) $(OBJCOPYFLAGS) $< $(@:.z64=.bin) -O binary
	$(N64CKSUM) $(@:.z64=.bin) $@

$(BUILD_DIR)/$(TARGET).objdump: $(ELF)
	$(OBJDUMP) -D $< > $@



.PHONY: all clean default diff test load libultra
.PRECIOUS: $(BUILD_DIR)/mio0/%.mio0 $(BUILD_DIR)/bin/%.elf $(BUILD_DIR)/mio0/%.mio0.s

# Remove built-in rules, to improve performance
MAKEFLAGS += --no-builtin-rules

-include $(DEP_FILES)

print-% : ; $(info $* is a $(flavor $*) variable set to [$($*)]) @true
