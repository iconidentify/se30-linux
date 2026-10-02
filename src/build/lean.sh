#!/bin/sh
# Apply the lean SE/30 kernel options to linux-7.2.8/.config.
cd /build/linux-7.2.8
scripts/config \
  --disable M68020 --disable M68040 --disable M68060 --enable M68030 \
  --disable INIT_STACK_ALL_ZERO --enable INIT_STACK_NONE \
  --disable HARDENED_USERCOPY --disable SLUB_DEBUG --disable BPF_SYSCALL \
  --disable NAMESPACES --disable NFS_FS --disable PROC_KCORE \
  --disable PREEMPT_VOLUNTARY --enable PREEMPT_NONE \
  --disable DEBUG_BUGVERBOSE --disable SCHED_DEBUG --disable DEBUG_FS \
  --disable FTRACE --disable LOGO \
  --disable ADB_IOP --disable ADB_CUDA --disable ADB_PMU
