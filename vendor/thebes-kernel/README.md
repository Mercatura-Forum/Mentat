# Thebes kernel

Mentat builds against the Thebes kernel at commit `233e233d2deb` (`233e233d2deb19e2928579c698a18ab83ebb3e5c`).
The kernel's public repository is published separately; until then this directory names the dependency
and the commit, and the tree type-checks once the kernel is placed here (`tools/packages.sh` reads
the kernel from this directory when it is present, and otherwise from a `thebes-kernel` checkout beside
this tree; `KERNEL=<path>` overrides both).

The ISO 20022 hub the payment battery validates against is public:
https://github.com/Mercatura-Forum/thebes-example-open-banking-iso20022 at commit `0de7a826b38f` (`0de7a826b38f493483c5ebc86ab6000a4102babe`).
