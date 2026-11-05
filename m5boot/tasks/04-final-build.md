# Task 04: final build

1. Apply review note R1: bound the payload trailer read by phys_base + mem_size, with a host test.
2. Wait until spec/inputs.md is updated by the other session (fixed initramfs /init + kernel without the hard-coded FB write; the superseded line marks the change). Then run tools/check-inputs.sh, build the final build/m5boot.bin, and run tests/qemu-j714s.sh with the new inputs (VM). Confirm /init stays up (no Attempted to kill init) and dropbear starts. Publish the final SHA-256 in NOTES.md.
End with DONE 04 (or BLOCKED 04 if inputs are not updated within the session).
