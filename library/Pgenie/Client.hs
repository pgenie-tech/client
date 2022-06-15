-- |
-- A thin wrapper over lean http client.
module Pgenie.Client
  ( Op,

    -- * Execution
    operateGlobally,

    -- * Operations
    process,
  )
where

import qualified Coalmine.EvenSimplerPaths as Path
import Coalmine.Prelude hiding (Op)
import qualified Data.Serialize as Cereal
import qualified Data.Text.IO as TextIO
import qualified LeanHttpClient as Lhc
import qualified Network.HTTP.Client as HttpClient
import qualified Network.HTTP.Client.TLS as HttpClientTls
import qualified Pgenie.Protocol.V1 as Protocol
import qualified System.Directory as Directory

-- | Execute operation on global manager.
operateGlobally :: Op a -> Bool -> Text -> Maybe Int -> IO (Either Text a)
operateGlobally (Op op) secure host port = do
  runReaderT op (secure, Lhc.textHost host, port)
    & Lhc.runSessionOnGlobalManager
    & fmap (first printErr)
  where
    -- TODO: Make prettier
    printErr = showAs

newtype Op a
  = Op (ReaderT (Bool, Lhc.Host, Maybe Int) Lhc.Session a)
  deriving (Functor, Applicative, Monad)

-- * Operations

executeRequest :: Protocol.Request -> Op Protocol.Response
executeRequest req =
  Op . ReaderT $ \(https, host, port) ->
    Lhc.post (url https host port) headers requestBody parser
  where
    url https host port =
      Lhc.url https host port path query
      where
        path = "/api/v1"
        query = []
    headers =
      mempty
    requestBody =
      Cereal.encode req
    parser = do
      Lhc.expectOkStatus
      Lhc.deserializeBodyWithCereal Cereal.get

process :: Name -> Name -> [(Path, Text)] -> [(Path, Text)] -> Op (Either Text [(Path, Text)])
process org name migrations queries = do
  fmap mapOut $
    executeRequest $
      Protocol.ProcessRequest $
        Protocol.RequestProcess org name migrations queries
  where
    mapOut = \case
      Protocol.FailedResponse err -> Left err
      Protocol.GeneratedResponse res -> Right res
