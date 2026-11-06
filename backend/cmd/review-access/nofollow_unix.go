//go:build unix

package main

import "syscall"

// oNofollow closes the Lstat-then-open race on the final path component:
// with it, the open itself refuses a symlink even if one appears (or is
// swapped in) after the Lstat pre-check above.
const oNofollow = syscall.O_NOFOLLOW
