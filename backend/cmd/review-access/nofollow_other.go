//go:build !unix

package main

// oNofollow is zero where the platform has no symlink-refusing open flag;
// the Lstat regular-file pre-check in writeProtected remains the guard.
const oNofollow = 0
