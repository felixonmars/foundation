-- |
-- Module      : Foundation.System.Entropy.Windows
-- License     : BSD-style
-- Maintainer  : Foundation
-- Stability   : experimental
-- Portability : Good
--
-- some code originally from cryptonite and some from the entropy package
--   Copyright (c) Thomas DuBuisson.
--
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE CPP #-}
module Foundation.System.Entropy.Windows
    ( EntropyCtx
    , entropyOpen
    , entropyGather
    , entropyClose
    ) where

import Data.Int (Int32)
import Data.Word
import Foreign.C.String (CString, withCString)
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Marshal.Utils (toBool)
import Foreign.Storable (peek)
import System.Win32.Types (getLastError)

newtype EntropyCtx = EntropyCtx CryptCtx

entropyOpen :: IO (Maybe EntropyCtx)
entropyOpen = EntropyCtx <$> cryptAcquireCtx

entropyGather :: EntropyCtx -> Ptr Word8 -> Int -> IO Int
entropyGather (EntropyCtx ctx) ptr n = cryptGenRandom ctx ptr n

entropyClose :: EntropyCtx -> IO ()
entropyClose (EntropyCtx ctx) = cryptReleaseCtx ctx

type DWORD = Word32
type BOOL  = Int32
type BYTE  = Word8

#if defined(ARCH_X86)
# define WINDOWS_CCONV stdcall
type CryptCtx = Word32
#elif defined(ARCH_X86_64)
# define WINDOWS_CCONV ccall
type CryptCtx = Word64
#else
# error Unknown mingw32 arch
#endif

-- Declare the required CryptoAPI imports
foreign import WINDOWS_CCONV unsafe "CryptAcquireContextA"
   c_cryptAcquireCtx :: Ptr CryptCtx -> CString -> CString -> DWORD -> DWORD -> IO BOOL
foreign import WINDOWS_CCONV unsafe "CryptGenRandom"
   c_cryptGenRandom :: CryptCtx -> DWORD -> Ptr BYTE -> IO BOOL
foreign import WINDOWS_CCONV unsafe "CryptReleaseContext"
   c_cryptReleaseCtx :: CryptCtx -> DWORD -> IO BOOL


-- Define the constants we need from WinCrypt.h
msDefProv :: String
msDefProv = "Microsoft Base Cryptographic Provider v1.0"

provRSAFull :: DWORD
provRSAFull = 1

cryptVerifyContext :: DWORD
cryptVerifyContext = 0xF0000000

cryptAcquireCtx :: IO (Maybe CryptCtx)
cryptAcquireCtx =
    alloca $ \handlePtr ->
    withCString msDefProv $ \provName -> do
        r <- toBool `fmap` c_cryptAcquireCtx handlePtr nullPtr provName provRSAFull cryptVerifyContext
        if r
            then Just `fmap` peek handlePtr
            else return Nothing

cryptGenRandom :: CryptCtx -> Ptr Word8 -> Int -> IO Int
cryptGenRandom h buf n = do
    success <- toBool `fmap` c_cryptGenRandom h (fromIntegral n) buf
    return $ if success then n else 0

cryptReleaseCtx :: CryptCtx -> IO ()
cryptReleaseCtx h = do
    success <- toBool `fmap` c_cryptReleaseCtx h 0
    if success
        then return ()
        else do
            lastError <- getLastError
            fail $ "cryptReleaseCtx: error " ++ show lastError
