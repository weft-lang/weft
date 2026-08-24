typedef signed char i8;
typedef unsigned char u8;
typedef short i16;
typedef unsigned short u16;
typedef int i32;
typedef unsigned int u32;
typedef long long i64;
typedef unsigned long long u64;
typedef long isize;
typedef unsigned long usize;

i64 abi_handle_value;
i64 abi_drop_counter;

void abi_nil(i64 value) { abi_handle_value = value; }
i8 abi_i8(i8 value) { return value; }
u8 abi_u8(u8 value) { return value; }
i16 abi_i16(i16 value) { return value; }
u16 abi_u16(u16 value) { return value; }
i32 abi_i32(i32 value) { return value; }
u32 abi_u32(u32 value) { return value; }
i64 abi_i64(i64 value) { return value; }
u64 abi_u64(u64 value) { return value; }
isize abi_isize(isize value) { return value; }
usize abi_usize(usize value) { return value; }
float abi_f32(float value) { return value; }
double abi_f64(double value) { return value; }
void *abi_open(i64 value) { abi_handle_value = value; return &abi_handle_value; }
i64 abi_opaque(void *raw) { return raw == &abi_handle_value ? *(i64 *)raw : -1; }
i64 abi_const_ptr(const u8 *raw) { return *raw; }
i64 abi_mut_ptr(u8 *raw, i64 value) { *raw = (u8)value; return *raw; }
i64 abi_const_bytes(const u8 *data, usize len) {
  i64 total = 0;
  for (usize i = 0; i < len; i += 1) total += data[i];
  return total;
}
i64 abi_mut_bytes(u8 *data, usize len, i64 value) {
  for (usize i = 0; i < len; i += 1) data[i] = (u8)value;
  return (i64)len;
}
i64 abi_arity8(i64 a, i64 b, i64 c, i64 d, i64 e, i64 f, i64 g, i64 h) {
  return a + b + c + d + e + f + g + h;
}
double abi_mixed(i64 a, double b, i64 c, double d) {
  return (double)(a + c) + b + d;
}
i32 abi_status(i32 fail) { return fail == 0 ? 0 : -7; }
void abi_close(void *raw) { if (raw == &abi_handle_value) abi_drop_counter += 1; }
i64 abi_drop_count(void) { return abi_drop_counter; }
