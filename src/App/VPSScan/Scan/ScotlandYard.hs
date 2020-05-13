module App.VPSScan.Scan.ScotlandYard
  ( createScan
  , postIprResults
  , HTTP(..)
  , runHTTP
  , ScanResponse(..)
  , ScotlandYard(..)
  , ScotlandYardC(..)
  , createScotlandYardScan
  , uploadIPRResults
  )
where
import Prologue

import Control.Algebra
import Control.Carrier.Error.Either
import Network.HTTP.Req
import App.VPSScan.Types
import OptionExtensions (UrlOption(..))

newtype HTTP a = HTTP { unHTTP :: ErrorC HttpException IO a }
  deriving (Functor, Applicative, Monad, MonadIO)

runHTTP :: MonadIO m => HTTP a -> m (Either HttpException a)
runHTTP = liftIO . runError @HttpException . unHTTP

instance MonadHttp HTTP where
  handleHttpException = HTTP . throwError

-- /projects/{projectID}/scans
createScanEndpoint :: Url 'Https -> Text -> Url 'Https
createScanEndpoint baseurl projectId = baseurl /: "projects" /: projectId /: "scans"

-- /projects/{projectID}/scans/{scanID}/discovered_licenses
scanDataEndpoint :: Url 'Https -> Text -> Text -> Url 'Https
scanDataEndpoint baseurl projectId scanId = baseurl /: "projects" /: projectId /: "scans" /: scanId /: "discovered_licenses"

data ScanResponse = ScanResponse
  { responseScanId :: Text
  } deriving (Eq, Ord, Show, Generic)

instance FromJSON ScanResponse where
  parseJSON = withObject "ScanResponse" $ \obj ->
    ScanResponse <$> obj .: "scanId"

createScan :: VPSOpts -> HTTP ScanResponse
createScan VPSOpts{..} = do
  let body = object ["organizationId" .= organizationID, "revisionId" .= revisionID, "projectId" .= projectID]
      ScotlandYardOpts{..} = vpsScotlandYard
  resp <- req POST (createScanEndpoint (urlOptionUrl scotlandYardUrl) projectID) (ReqBodyJson body) jsonResponse (urlOptionOptions scotlandYardUrl <> header "Content-Type" "application/json")
  pure (responseBody resp)

-- Given the results from a run of IPR, a scan ID and a URL for Scotland Yard,
-- post the IPR result to the "Upload Scan Data" endpoint on Scotland Yard
-- POST /scans/{scanID}/discovered_licenses
postIprResults :: ToJSON a => VPSOpts -> Text -> a -> HTTP ()
postIprResults VPSOpts{..} scanId value = do
  let ScotlandYardOpts{..} = vpsScotlandYard
  _ <- req POST (scanDataEndpoint (urlOptionUrl scotlandYardUrl) projectID scanId) (ReqBodyJson value) ignoreResponse (urlOptionOptions scotlandYardUrl <> header "Content-Type" "application/json")
  pure ()

----- scotland yard effect

data ScotlandYard m k where
  CreateScotlandYardScan :: VPSOpts -> ScotlandYard m (Either HttpException ScanResponse)
  UploadIPRResults :: VPSOpts -> Text -> Value -> ScotlandYard m (Either HttpException ())

createScotlandYardScan :: Has ScotlandYard sig m => VPSOpts -> m (Either HttpException ScanResponse)
createScotlandYardScan vpsOpts = send (CreateScotlandYardScan vpsOpts)

uploadIPRResults :: Has ScotlandYard sig m => VPSOpts -> Text -> Value -> m (Either HttpException ())
uploadIPRResults vpsOpts scanId value = send (UploadIPRResults vpsOpts scanId value)

----- scotland yard production interpreter

newtype ScotlandYardC m a = ScotlandYardC { runScotlandYard :: m a }
  deriving (Functor, Applicative, Monad, MonadIO)

instance (Algebra sig m, MonadIO m) => Algebra (ScotlandYard :+: sig) (ScotlandYardC m) where
  alg hdl sig ctx = ScotlandYardC $ case sig of
    R other -> alg (runScotlandYard . hdl) other ctx
    L (CreateScotlandYardScan vpsOpts) -> (<$ ctx) <$> runHTTP (createScan vpsOpts)
    L (UploadIPRResults vpsOpts scanId value) -> (<$ ctx) <$> runHTTP (postIprResults vpsOpts scanId value)
