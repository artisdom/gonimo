{-# LANGUAGE TypeFamilies #-}
-- | Functions for working with Family entity
--   This module is intended to be imported qualified as Family
module Gonimo.Server.Db.Family where

import           Control.Monad                   (MonadPlus, guard)
import           Control.Monad.State.Class
import           Control.Monad.Trans.Maybe       (MaybeT)
import           Data.Text                       (Text)
import           Data.Maybe                      (listToMaybe)

import           Gonimo.Server.Error             (ServerError (NoSuchFamily))

import           Gonimo.Db.Entities       (FamilyId)
import           Gonimo.Db.Entities       (Family (..))
import           Gonimo.Server.Db.Internal       (updateRecord, UpdateT)
import           Control.Monad.Base              (MonadBase)
import           Control.Monad.IO.Class          (MonadIO)
import           Database.Persist.Class          (PersistEntity,
                                                  PersistEntityBackend,
                                                  PersistStore)
import           Control.Monad.Trans.Reader      (ReaderT (..))
import qualified Gonimo.Types as Gonimo

type UpdateFamilyT m a = UpdateT Family m a

pushBabyName :: (MonadState Family m, MonadPlus m) => Text -> m ()
pushBabyName name = do
  oldFamily <- get
  let oldBabies = familyLastUsedBabyNames oldFamily
  guard $ (Just name /= listToMaybe oldBabies)
  put $ oldFamily
    { familyLastUsedBabyNames = take 5 (name : filter (/= name) oldBabies)
    }

setFamilyName :: (MonadState Family m, MonadPlus m) => Text -> m ()
setFamilyName name = do
  oldFamily <- get
  let oldName = familyName oldFamily
  guard $ name /= Gonimo.familyName oldName
  put $ oldFamily
    { familyName = oldName { Gonimo.familyName = name }
    }

-- | Update db entity as specified by the given UpdateFamilyT - on Nothing, no update occurs.
update :: (PersistEntity Family, backend ~ PersistEntityBackend Family
          , MonadIO m, MonadBase IO m, PersistStore backend)
          => FamilyId -> UpdateFamilyT (ReaderT backend m) a -> MaybeT (ReaderT backend m) a
update = updateRecord NoSuchFamily

