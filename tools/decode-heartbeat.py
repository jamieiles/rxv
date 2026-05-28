#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "capstone",
#   "docopt-ng"
# ]
# ///
"""decode-heartbeat.py

Decode heartbeat logs to print disassembled instructions

Usage:
  decode-heartbeat.py <FILENAME>

Options:
  <FILENAME>  Path to the heartbeat log
"""
import capstone
import sys
from docopt import docopt

def decode(filename: str) -> None:
    md = capstone.Cs(capstone.CS_ARCH_RISCV, capstone.CS_MODE_32)

    with open(filename) as hb:
        lines = hb.readlines()

    for line in lines:
        words = line.rstrip().split()
        insn_bytes = int(words[-1], 16).to_bytes(4)[::-1]
        for insn in md.disasm(insn_bytes, int(words[-2], 16)):
            print(' '.join(words[0:-1] + [f'{insn.mnemonic} {insn.op_str}']))


if __name__ == '__main__':
    args = docopt(__doc__)

    decode(args['<FILENAME>'])
