{-# LANGUAGE DataKinds, KindSignatures, RankNTypes, StandaloneDeriving, GADTs, TypeOperators
           , FlexibleInstances, ViewPatterns, UndecidableInstances #-}

--                    var intro     lambda body             v--- app ---v
data Place' = Root' | Def' Place' | Body' Place' | Lunder' Place' | Runder' Place'

class KnownPlace (p :: Place') where
  thePlace :: Place p

-- value inference for a place type
instance KnownPlace Root' where thePlace = Root
instance KnownPlace p => KnownPlace (Def' p) where thePlace = Def
instance KnownPlace p => KnownPlace (Body' p) where thePlace = Body
instance KnownPlace p => KnownPlace (Lunder' p) where thePlace = Lunder
instance KnownPlace p => KnownPlace (Runder' p) where thePlace = Runder

-- singleton type isomorphic to (promoted) kind Place'
data Place :: Place' -> * where
  Root :: Place Root'
  Def :: KnownPlace p => Place (Def' p)
  Body :: KnownPlace p => Place (Body' p)
  Lunder :: KnownPlace p => Place (Lunder' p)
  Runder :: KnownPlace p => Place (Runder' p)

data Nat' = Z' | S' Nat'

data Nat :: Nat' -> * where
  Z :: Nat Z'
  S :: Nat n -> Nat (S' n)

class KnownNat (n :: Nat') where
  theNat :: Nat n

instance KnownNat Z' where
  theNat = Z

instance KnownNat n => KnownNat (S' n) where
  theNat = S theNat

deriving instance Show (Nat n)

-- Def-Use markers

type PlusFour n = S' (S' (S' (S' n)))
type PlusFive n = S' (PlusFour n)
type PlusTen n = PlusFive (PlusFive n)


----------- def     use
data Lam :: Nat' -> Nat' -> * where
  Dummy :: (KnownNat d, KnownNat u) => Lam d u -- only for Show!
  L :: (KnownNat d, KnownNat u) => ((forall u . KnownNat u => Lam (S' d) u) -> Lam (S' d) u) -> Lam d u
  (:&) :: (KnownNat d, KnownNat d', KnownNat d'', KnownNat u) => (Lam d' (PlusFour d)) -> (Lam d'' (PlusFive d)) -> Lam d u

instance Show (Lam def use) where
  show lam@(L f) = "(\\" ++ show (f Dummy) ++ ")" ++ duStr lam
  show all@(f :& a) = "(" ++ show f ++ " & " ++ show a ++ ")" ++ duStr all
  show d@Dummy = duStr d

duStr :: forall def use . (KnownNat def, KnownNat use) => Lam def use -> String
duStr l = "d" ++ nat2str (def l) ++ "u" ++ nat2str (use l)

def :: KnownNat def => Lam def use -> Nat def
def _ = theNat
use :: KnownNat use => Lam def use -> Nat use
use _ = theNat

nat2int :: Nat n -> Int
nat2int Z = 0
nat2int (S n) = nat2int n + 1

nat2str = show . nat2int

test :: Lam Z' (PlusTen Z')
test = L (\a -> a :& a)
test' :: Lam Z' Z'
test' = L $ \x->x
test'' :: Lam Z' Z'
test'' = L $ \x->L $ \x->x
