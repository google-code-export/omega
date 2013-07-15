{-# LANGUAGE KindSignatures, DataKinds, TypeOperators, StandaloneDeriving, GADTs,
             MultiParamTypeClasses, FlexibleInstances, FlexibleContexts,
             UndecidableInstances, TypeHoles #-}

-- See: https://code.google.com/p/omega/wiki/LambdaGraph

data {-kind-} Lam = Var Lam | App Lam Lam | Abs Lam | Ref [Go]
data {-kind-} Go = Up | Le | Ri | Down

data {-kind-} Trace = Root Lam | VarD Trace Lam | AppL Trace Lam | AppR Trace Lam | AbsD Trace Lam

-- a zipper for lambda trees
--
data Traced :: Trace -> * where
  EmptyRoot :: Builder l => l sh -> Traced (Root sh)
  VarDown :: Builder l => Traced tr -> l (Var sh) -> Traced (VarD tr sh)
  AppLeft :: Builder l => Traced tr -> l (App shl shr) -> Traced (AppL tr shl)
  AppRight :: Builder l => Traced tr -> l (App shl shr) -> Traced (AppR tr shr)
  AbsDown :: Builder l => Traced tr -> l (Abs sh) -> Traced (AbsD tr sh)

--deriving instance Show (Traced tr)

class Builder (shape :: Lam -> *) where
  v :: shape inner -> shape (Var inner)
  lam :: shape inner -> shape (Abs inner)
  app :: shape left -> shape right -> shape (App left right)
  here :: shape (Ref '[Up])
  up :: shape (Ref p) -> shape (Ref (Up ': p))
  close :: Closed sh env => Traced env -> shape sh -> shape sh
  checkClosure :: Traced env -> shape sh -> Proven sh env

class Closed (sh :: Lam) (env :: Trace)
instance Closed (Ref '[]) env
instance Closed (Ref more) up => Closed (Ref (Up ': more)) ((down :: Trace -> Lam -> Trace) up sh)
instance Closed below (VarD env below) => Closed (Var below) env
instance Closed below (AbsD env below) => Closed (Abs below) env
instance (Closed left (AppL env left), Closed right (AppR env right)) => Closed (App left right) env

instance Closed below (VarD env below) => Closed (Var down) (VarD env (Var down))

data Proven :: Lam -> Trace -> * where
  NoWay :: Proven sh env
  TrivialRef :: Proven (Ref '[]) env
  ProvenRefUp :: Closed (Ref more) env => Proven (Ref more) env -> Proven (Ref (Up ': more)) ((down :: Trace -> Lam -> Trace) env stuff)
  ProvenApp :: (Closed l (AppL env l), Closed r (AppR env r)) =>
               Proven l (AppL env l) -> Proven r (AppR env r) ->
               Proven (App l r) env
  ProvenVar :: Closed below (VarD env below) =>
               Proven below (VarD env below) -> Proven (Var below) env

  ProvenDown :: Closed (Ref more) up =>
                Closed (Ref more) up -> Proven below (VarD env below)

--prove :: Classical sh -> 

proveRef :: Classical (Ref more) -> Traced env -> Proven (Ref more) env
proveRef HERE (VarDown _ _) = ProvenRefUp TrivialRef
proveRef HERE (AbsDown _ _) = ProvenRefUp TrivialRef
proveRef HERE (AppLeft _ _) = ProvenRefUp TrivialRef
proveRef HERE (AppRight _ _) = ProvenRefUp TrivialRef
proveRef (UP and) (VarDown up _) = case (proveRef and up) of
                                   NoWay -> NoWay
                                   p@(ProvenRefUp _) -> ProvenRefUp p
proveRef (UP and) (AbsDown up _) = case (proveRef and up) of
                                   NoWay -> NoWay
                                   p@(ProvenRefUp _) -> ProvenRefUp p
proveRef (UP and) (AppLeft up _) = case (proveRef and up) of
                                   NoWay -> NoWay
                                   p@(ProvenRefUp _) -> ProvenRefUp p
proveRef (UP and) (AppRight up _) = case (proveRef and up) of
                                    NoWay -> NoWay
                                    p@(ProvenRefUp _) -> ProvenRefUp p



proveVar :: Classical (Var sh) -> Traced env -> Proven (Var sh) env
proveVar v@(VAR h@HERE)  env = ProvenVar $ proveRef h (VarDown env v)
proveVar v@(VAR u@(UP _))  env = case proveRef u (VarDown env v) of
                                 NoWay -> NoWay
                                 p@(ProvenRefUp _) -> ProvenVar p
proveVar (VAR a@(APP _ _))  env = case proveApp a (AppLeft env a) of -- proveDown!!!
                                  NoWay -> NoWay
                                  p@(ProvenApp _ _) -> undefined -- ProvenVar p

proveApp :: Classical (App l r) -> Traced env -> Proven (App l r) env
proveApp v@(APP h@HERE h2@HERE)  env = undefined -- case proveRef h (AppL env v)

data Classical :: Lam -> * where
  LAM :: Classical sh -> Classical (Abs sh)
  APP :: Classical left -> Classical right -> Classical (App left right)
  VAR :: Classical sh -> Classical (Var sh)
  HERE :: Classical (Ref '[Up])
  UP :: Classical (Ref more) -> Classical (Ref (Up ': more))

deriving instance Show (Classical sh)

instance Builder Classical where
  lam = LAM
  app = APP
  v = VAR
  here = HERE
  up = UP


-- TESTS
-- ######

t1 = v HERE
t1' = close (EmptyRoot t1) t1

t2 = app t1 t1
t2' = close (EmptyRoot t2) t2

