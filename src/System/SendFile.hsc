{-# LANGUAGE BangPatterns             #-}
{-# LANGUAGE CPP                      #-}
{-# LANGUAGE ForeignFunctionInterface #-}

-- | Snap's unified interface to sendfile.
-- Modified from sendfile 0.6.1

module System.SendFile
  ( sendFile
  , sendFileMode
  , sendHeaders
  ) where

#include <sys/socket.h>

import           Blaze.ByteString.Builder
import           Control.Concurrent       (threadWaitWrite)
import qualified Data.ByteString.Unsafe   as S
import           Data.Int
import           Foreign.C.Error          (throwErrnoIfMinus1RetryMayBlock)
#if __GLASGOW_HASKELL__ >= 703
import           Foreign.C.Types          (CChar (..), CInt (..), CSize (..))
#else
import           Foreign.C.Types          (CChar, CInt, CSize)
#endif
import           Foreign.Ptr              (Ptr, plusPtr)
#if __GLASGOW_HASKELL__ >= 703
import           System.Posix.Types       (Fd (..))
#else
import           System.Posix.Types       (COff, CSsize, Fd)
#endif

#if defined(LINUX)
import qualified System.SendFile.Linux    as SF
#elif defined(FREEBSD)
import qualified System.SendFile.FreeBSD  as SF
#elif defined(OSX)
import qualified System.SendFile.Darwin   as SF
#endif


------------------------------------------------------------------------------
sendFile :: Fd                  -- ^ out fd (i.e. the socket)
         -> Fd                  -- ^ in fd (i.e. the file)
         -> Int64               -- ^ offset in bytes
         -> Int64               -- ^ count in bytes
         -> IO ()
sendFile out_fd in_fd = go
  where
    go !offs !count | count <= 0 = return $! ()
                    | otherwise  = do nsent <- SF.sendFile out_fd in_fd
                                                           offs count
                                      go (offs + nsent) (count - nsent)


------------------------------------------------------------------------------
sendFileMode :: String
sendFileMode = SF.sendFileMode


------------------------------------------------------------------------------
sendHeaders :: Builder -> Fd -> IO ()
sendHeaders headers fd =
    S.unsafeUseAsCStringLen (toByteString headers) $
         \(cstr, clen) -> go cstr (fromIntegral clen)
  where
#if defined(LINUX)
    flags = (#const MSG_MORE)
#else
    flags = 0
#endif

    go !cstr !clen | clen <= 0 = return ()
                   | otherwise = do
                         nsent <- throwErrnoIfMinus1RetryMayBlock
                                     "sendHeaders"
                                     (c_send fd cstr clen flags)
                                     (threadWaitWrite fd)
                         let cstr' = plusPtr cstr (fromIntegral nsent)
                         go cstr' (clen - nsent)


------------------------------------------------------------------------------
foreign import ccall unsafe "sys/socket.h send" c_send
    :: Fd -> Ptr CChar -> CSize -> CInt -> IO CSize
