#! /bin/bash -eu

# Generate xlat .in file based on existing file and Linux UAPI headers.
#
# Copyright (c) 2018 The strace developers.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

usage() {
cat >&2 <<-EOF
$0 [-p PATTERN] [-d LINUX_SRC_DIR] [-c COMMON_DEFS_GLOB]
${0//?/ } [-a ARCH_DEFS_GLOB] [-f VAL_PRINT_FMT] XLAT_FILE

  -p PATTERN         - xlat constant pattern
  -d LINUX_SRC_DIR   - directory that contains git checkout of the Linux
                       repository.
  -c COMMON_DEF_GLOB - glob pattern for the files under include/uapi
                       that contain the desired definitions.
  -a ARCH_DEFS_GLOB  - glob pattern for the files under arch/*/include/uapi
                       that contain the desired definitons.
  -f VAL_PRINT_FMT   - printf conversion specification (without the leading
                       percent sign) for the constant values.
  XLAT_FILE          - xlat file name (without leading "xlat/" and terminating
                       ".in")

Example: $0 -f '#x' -p '_?MAP_' -c 'asm-generic/mman*.h' -a 'asm/mman.h' -d /path/to/linux/src mmap_flags
EOF
	exit 1
}

pattern=
xlat_file=
linux_src=
common_path=
arch_path=
val_fmt="#o"

while [ 0 -lt "$#" ]; do
	case "$1" in
	-p)
		shift
		pattern="$1"
		;;
	-d)
		shift
		linux_src="$1"
		;;
	-c)
		shift
		common_path="$1"
		;;
	-a)
		shift
		arch_path="$1"
		;;
	-f)
		shift
		val_fmt="$1"
		;;
	-[h?])
		usage
		;;
	-*)
		echo "$1: unknown option" >&2
		usage
		;;
	*)
		[ 1 -eq "$#" ] || usage
		xlat_file="$1"
		;;
	esac

	shift
done

[ -n "$pattern" -a -n "$xlat_file" -a -n "$linux_src" -a -n "$common_path" -a -n "$arch_path" ] || {
	echo "No xlat file specified." >&2
	usage
}

sed -rn 's/^('"$pattern"'[^[:space:]]*).*/\1/p' "xlat/${xlat_file}.in" | uniq |
    while read name_ rest; do
	sed -rn 's/#define[[:space:]]+('"$name_"')[[:space:]]+([x[:xdigit:]]+).*$/\2\t\1/p' \
	   $linux_src/include/uapi/$common_path | sort -n | {
		read def name || :

		if [ -n "$def" ]; then
			echo "$name_ is defined to $def" >&2
		else
			echo "No def for $name_" >&2
			name="$name_"
		fi

		grep -oEH '#define[[:space:]]+'"$name"'[[:space:]]+(0x[[:xdigit:]]+|[[:digit:]]+)' \
		    $linux_src/arch/*/include/uapi/$arch_path |
		    sed -rn 's|^[^#]*/arch/([^/]+)/include/uapi/'"$arch_path"':#define[[:space:]]+'"$name"'[[:space:]]+([^[:space:]]+)([[:space:]].*)?$|\1\t\2|p' |
		    sed s/parisc/hppa/ | sort |
		    awk -vname="$name" -vdef="$def" -vfmt="$val_fmt" '
			# Like strtonum, but also supports octal and hexadecimal
			# representation.
			# Taken from https://www.gnu.org/software/gawk/manual/html_node/Strtonum-Function.html
			function mystrtonum(str,        ret, n, i, k, c)
			{
				if (str ~ /^0[0-7]*$/) {
					# octal
					n = length(str)
					ret = 0
					for (i = 1; i <= n; i++) {
						c = substr(str, i, 1)
						# index() returns 0 if c not in string,
						# includes c == "0"
						k = index("1234567", c)

						ret = ret * 8 + k
					}
				} else if (str ~ /^0[xX][[:xdigit:]]+$/) {
					# hexadecimal
					str = substr(str, 3) # lop off leading 0x
					n = length(str)
					ret = 0

					for (i = 1; i <= n; i++) {
						c = substr(str, i, 1)
						c = tolower(c)
						# index() returns 0 if c not in string,
						# includes c == "0"
						k = index("123456789abcdef", c)

						ret = ret * 16 + k
					}
				} else if (str ~ \
				    /^[-+]?([0-9]+([.][0-9]*([Ee][0-9]+)?)?|([.][0-9]+([Ee][-+]?[0-9]+)?))$/) {
					# decimal number, possibly floating point
					ret = str + 0
				} else {
					ret = "NOT-A-NUMBER"
				}

				return ret
			}

			BEGIN {
				d = mystrtonum(def)
			}

			{
				i = mystrtonum($2)
				if (i == d) next
				if (a[i])
					a[i] = a[i] " || defined __" $1 "__"
				else
					a[i] = "defined __" $1 "__"
			}

			END {
				iftext = "#if"
				for (i in a) {
					printf("%s %s\n%s\t%" fmt "\n", iftext, a[i],
					       name, i)
					iftext = "#elif"
				}

				if (iftext != "#if")
					print "#else"

				if (def == "")
					printf("%s\n", name)
				else
					printf("%s\t%" fmt "\n", name, d)

				if (iftext == "#if")
					print ""
				else
					print "#endif\n"
			}' |
		    sed 's/defined __arm64__/defined __aarch64__ || defined __arm64__/g'
	}
done
