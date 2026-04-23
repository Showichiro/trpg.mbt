///|
#borrow(bytes)
extern "C" fn write_stdout_ffi(bytes : Bytes) -> Unit = "trpg_write_stdout"

///|
#borrow(bytes)
extern "C" fn write_stderr_ffi(bytes : Bytes) -> Unit = "trpg_write_stderr"

///|
fn write_stdout(text : String) -> Unit {
  write_stdout_ffi(@utf8.encode(text))
}

///|
fn write_stderr(text : String) -> Unit {
  write_stderr_ffi(@utf8.encode(text))
}
