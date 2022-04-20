{-# LANGUAGE RecordWildCards #-}

module App.Fossa.Config.Container.Dump (
  ContainerDumpScanOptions (..),
  ContainerDumpScanConfig (..),
  mergeOpts,
  cliParser,
  subcommand,
) where

import App.Fossa.Config.ConfigFile (ConfigFile)
import App.Fossa.Config.Container.Common (ImageText, imageTextArg)
import App.Fossa.Config.EnvironmentVars (EnvVars)
import Control.Algebra (Has)
import Control.Effect.Diagnostics (Diagnostics)
import Control.Effect.Lift (Lift)
import Data.Aeson (ToJSON (toEncoding), defaultOptions, genericToEncoding)
import Data.Text (Text)
import Effect.ReadFS (ReadFS, getCurrentDir, resolveFile)
import GHC.Generics (Generic)
import Options.Applicative (
  CommandFields,
  Mod,
  Parser,
  command,
  help,
  info,
  long,
  optional,
  progDesc,
  short,
  strOption,
 )
import Path (Abs, File, Path)

subcommand :: (ContainerDumpScanOptions -> a) -> Mod CommandFields a
subcommand f =
  command
    "dump-scan"
    ( info (f <$> cliParser) $
        progDesc "Capture syft output for debugging"
    )

data ContainerDumpScanOptions = ContainerDumpScanOptions
  { dumpScanOutputFile :: Maybe Text
  , dumpScanImage :: ImageText
  }

data ContainerDumpScanConfig = ContainerDumpScanConfig
  { outputFile :: Maybe (Path Abs File)
  , dumpImageLocator :: ImageText
  }
  deriving (Eq, Ord, Show, Generic)

instance ToJSON ContainerDumpScanConfig where
  toEncoding = genericToEncoding defaultOptions

mergeOpts ::
  ( Has (Lift IO) sig m
  , Has ReadFS sig m
  , Has Diagnostics sig m
  ) =>
  Maybe ConfigFile ->
  EnvVars ->
  ContainerDumpScanOptions ->
  m ContainerDumpScanConfig
mergeOpts _ _ ContainerDumpScanOptions{..} = do
  curdir <- getCurrentDir
  maybeOut <- case dumpScanOutputFile of
    Nothing -> pure Nothing
    Just fp -> Just <$> resolveFile curdir fp
  pure $ ContainerDumpScanConfig maybeOut dumpScanImage

cliParser :: Parser ContainerDumpScanOptions
cliParser =
  ContainerDumpScanOptions
    <$> optional
      ( strOption
          ( short 'o'
              <> long "output-file"
              <> help "File to write the scan data (omit for stdout)"
          )
      )
    <*> imageTextArg
