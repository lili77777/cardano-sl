{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Part of GState DB which stores data necessary for heavyweight delegation.

module Pos.DB.GState.Delegation
       ( getPSKByIssuer
       , DelegationOp (..)
       , IssuerPublicKey (..)
       , iteratePSKs
       ) where

import           Data.Binary       (Get)
import qualified Database.RocksDB  as Rocks
import           Universum

import           Pos.Binary.Class  (Bi (..), encodeStrict)
import           Pos.Crypto        (PublicKey, pskIssuerPk)
import           Pos.DB.Class      (MonadDB, getUtxoDB)
import           Pos.DB.DBIterator (DBMapIterator, mapIterator)
import           Pos.DB.Functions  (RocksBatchOp (..), rocksGetBi)
import           Pos.Types         (ProxySKSimple)


----------------------------------------------------------------------------
-- Getters/direct accessors
----------------------------------------------------------------------------

-- | Retrieves certificate by issuer public key if present.
getPSKByIssuer :: MonadDB ssc m => PublicKey -> m (Maybe ProxySKSimple)
getPSKByIssuer issuerPk =
    rocksGetBi (pskKey $ IssuerPublicKey issuerPk) =<< getUtxoDB

----------------------------------------------------------------------------
-- Batch operations
----------------------------------------------------------------------------

data DelegationOp
    = AddPSK !ProxySKSimple
    -- ^ Adds PSK. Overwrites if present.
    | DelPSK !PublicKey
    -- ^ Removes PSK by issuer PK.

instance RocksBatchOp DelegationOp where
    toBatchOp (AddPSK psk) =
        [Rocks.Put (pskKey $ IssuerPublicKey $ pskIssuerPk psk) (encodeStrict psk)]
    toBatchOp (DelPSK issuerPk) =
        [Rocks.Del $ pskKey $ IssuerPublicKey issuerPk]

----------------------------------------------------------------------------
-- Iteration
----------------------------------------------------------------------------

type IterType = (IssuerPublicKey,ProxySKSimple)

iteratePSKs :: forall v m ssc a . (MonadDB ssc m, MonadMask m)
                => DBMapIterator (IterType -> v) m a -> (IterType -> v) -> m a
iteratePSKs iter f = mapIterator @IterType @v iter f =<< getUtxoDB

----------------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------------

-- [CSL-379] Restore prefix after we have proper iterator
newtype IssuerPublicKey = IssuerPublicKey PublicKey

instance Bi IssuerPublicKey where
    put (IssuerPublicKey p) = put ("d/" :: ByteString) >> put p -- chto by eto ne znaczilo
    get = (get :: Get ByteString) >> IssuerPublicKey <$> get

-- Storing IssuerPk -> ProxySKSimple
pskKey :: IssuerPublicKey -> ByteString
pskKey = encodeStrict
