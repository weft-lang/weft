# Array mutation controls

These ordinary-language programs check fixed-array mutation with and without
a retained immutable snapshot. Time `mutation_exclusive.weft` and
`mutation_shared.weft` separately: a gain from reusing exclusive storage must
not conceal a regression in required copies. Their kernels are identical;
only the selected sharing mode and expected checksum differ.

Each separate control performs 100,000 mutations. `mutation.weft` exercises
both modes at 10,000 mutations each for the combined allocation census.
Every product must exit zero before its timing is used.

```bash
./weft build bench/arrays/mutation_exclusive.weft -o /tmp/weft-array-exclusive
./weft build bench/arrays/mutation_shared.weft -o /tmp/weft-array-shared
```
