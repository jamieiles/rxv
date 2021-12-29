#!/usr/bin/env python3
import os
import re
import subprocess
import sys

TEST_RE = r'.*rv32[msu][aim]-[pv]-[^\.]*$'

PRIV_TESTS = [
    "ebreak",
    "ecall",
    "misalign-sw-01",
    "misalign-sh-01",
    "misalign-lw-01",
    "misalign-lhu-01",
    "misalign-lh-01",
]

ISAS = ["I", "M", "Zifencei", "privilege"]


def run_priv_test(sim, src, obj, target_dir, isa, test):
    cmd_prefix = ['make', '-C', src, f'WORK={obj}', f'RISCV_SIMULATOR={sim}',
                  f'TARGETDIR={target_dir}', f'RISCV_TARGET=rxv-simulator',
                  f'RISCV_DEVICE={isa}', '-j1', f'rv32i_sc_tests={test}']
    subprocess.check_call(cmd_prefix + ['simulate'])
    subprocess.check_call(cmd_prefix + ['verify'])


def run_test(sim, src, obj, target_dir, isa):
    cmd_prefix = ['make', '-C', src, f'WORK={obj}', f'RISCV_SIMULATOR={sim}',
                  f'TARGETDIR={target_dir}', f'RISCV_TARGET=rxv-simulator',
                  f'RISCV_DEVICE={isa}', '-j1']
    subprocess.check_call(cmd_prefix + ['simulate'])
    subprocess.check_call(cmd_prefix + ['verify'])


def run_tests(sim, src, obj, target_dir):
    failures = []

    for isa in ISAS:
        if isa == "privilege":
            for test in PRIV_TESTS:
                try:
                    run_priv_test(sim, src, obj, target_dir, isa, test)
                except subprocess.CalledProcessError:
                    failures.append(f'{isa}_{test}')
        else:
            try:
                run_test(sim, src, obj, target_dir, isa)
            except subprocess.CalledProcessError:
                failures.append(isa)

    if failures:
        print('TESTS FAILED:')
        print('\n'.join(failures))
        sys.exit(1)


def main():
    if len(sys.argv) != 5:
        print('usage: {0} sim src obj target_dir'.format(
            sys.argv[0]), file=sys.stderr)
        sys.exit(2)
    run_tests(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])


if __name__ == '__main__':
    main()
