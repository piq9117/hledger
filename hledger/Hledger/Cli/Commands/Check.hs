{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Check (
  checkmode
 ,check
) where

import Data.Char (toLower)
import Data.Either (partitionEithers)
import Data.List (isPrefixOf, find)
import Control.Monad (forM_)
import System.Console.CmdArgs.Explicit

import Hledger
import Hledger.Cli.CliOptions

checkmode :: Mode RawOpts
checkmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Check.txt")
  []
  [generalflagsgroup1]
  hiddenflags
  ([], Just $ argsFlag "[CHECKS]")

check :: CliOpts -> Journal -> IO ()
check copts@CliOpts{rawopts_} j = do
  let 
    args = listofstringopt "args" rawopts_
    -- reset the report spec that was generated by argsToCliOpts,
    -- since we are not using arguments as a query in the usual way
    copts' = cliOptsUpdateReportSpecWith (\ropts -> ropts{querystring_=[]}) copts

  case partitionEithers (map parseCheckArgument args) of
    (unknowns@(_:_), _) -> error' $ "These checks are unknown: "++unwords unknowns
    ([], checks) -> forM_ checks $ runCheck copts' j
      
-- | Regenerate this CliOpts' report specification, after updating its
-- underlying report options with the given update function.
-- This can raise an error if there is a problem eg due to missing or
-- unparseable options data. See also updateReportSpecFromOpts.
cliOptsUpdateReportSpecWith :: (ReportOpts -> ReportOpts) -> CliOpts -> CliOpts
cliOptsUpdateReportSpecWith roptsupdate copts@CliOpts{reportspec_} =
  case updateReportSpecWith roptsupdate reportspec_ of
    Left e   -> error' e  -- PARTIAL:
    Right rs -> copts{reportspec_=rs}

-- | A type of error check that we can perform on the data.
-- Some of these imply other checks that are done first,
-- eg currently Parseable and Autobalanced are always done,
-- and Assertions are always done unless -I is in effect.
data Check =
  -- done always
    Parseable
  | Autobalanced
  -- done always unless -I is used
  | Assertions
  -- done when -s is used, or on demand by check
  | Accounts
  | Commodities
  | Balanced
  -- done on demand by check
  | Ordereddates
  | Payees
  | Recentassertions
  | Tags
  | Uniqueleafnames
  deriving (Read,Show,Eq,Enum,Bounded)

-- | Parse the name (or a name prefix) of an error check, or return the name unparsed.
-- Check names are conventionally all lower case, but this parses case insensitively.
parseCheck :: String -> Either String Check
parseCheck s = 
  maybe (Left s) (Right . read) $  -- PARTIAL: read should not fail here
  find (s' `isPrefixOf`) $ checknames
  where
    s' = capitalise $ map toLower s
    checknames = map show [minBound..maxBound::Check]

-- | Parse a check argument: a string which is the lower-case name of an error check,
-- or a prefix thereof, followed by zero or more space-separated arguments for that check.
parseCheckArgument :: String -> Either String (Check,[String])
parseCheckArgument s =
  dbg3 "check argument" $
  ((,checkargs)) <$> parseCheck checkname
  where
    (checkname:checkargs) = words' s

-- XXX do all of these print on stderr ?
-- | Run the named error check, possibly with some arguments, 
-- on this journal with these options.
runCheck :: CliOpts -> Journal -> (Check,[String]) -> IO ()
runCheck _opts j (chck,_) = do
  d <- getCurrentDay
  let
    results = case chck of
      Accounts        -> journalCheckAccounts j
      Commodities     -> journalCheckCommodities j
      Ordereddates    -> journalCheckOrdereddates j
      Payees          -> journalCheckPayees j
      Recentassertions -> journalCheckRecentAssertions d j
      Tags            -> journalCheckTags j
      Uniqueleafnames -> journalCheckUniqueleafnames j
      -- the other checks have been done earlier during withJournalDo
      _               -> Right ()

  case results of
    Right () -> return ()
    Left err -> error' err
