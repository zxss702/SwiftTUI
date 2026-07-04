// Copyright © 2025 Saleem Abdulrasool <compnerd@compnerd.org>
// SPDX-License-Identifier: BSD-3-Clause

#if canImport(Musl)

@_exported
import Musl

@_transparent
package var _SC_PAGESIZE: CInt {
  CInt(Musl._SC_PAGESIZE)
}

@_transparent
public var ECHO: tcflag_t {
  tcflag_t(Musl.ECHO)
}

@_transparent
public var ICANON: tcflag_t {
  tcflag_t(Musl.ICANON)
}

@_transparent
public var ICRNL: tcflag_t {
  tcflag_t(Musl.ICRNL)
}

@_transparent
public var IXON: tcflag_t {
  tcflag_t(Musl.IXON)
}

@_transparent
public var TIOCGWINSZ: CUnsignedLong {
  CUnsignedLong(Musl.TIOCGWINSZ)
}

#endif
