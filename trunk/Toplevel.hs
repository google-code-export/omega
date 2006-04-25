-- Copyright (c) Tim Sheard
-- OGI School of Science & Engineering, Oregon Health & Science University
-- Maseeh College of Engineering, Portland State University
-- Subject to conditions of distribution and use; see LICENSE.txt for details.
-- Tue Apr 25 12:54:27 Pacific Daylight Time 2006
-- Omega Interpreter: version 1.2.1


module Toplevel where

import Time
import Version(version,buildtime)
import Syntax
import ParserDef(getInt,pCommand,parseString,Command(..)
                ,program,parseHandle)
import LangEval(Env(..),env0,eval,elaborate,Prefix(..),mPatStrict,extendV)
import Monads(FIO(..),unFIO,runFIO,fixFIO,fio,resetNext
             ,write,writeln,readln,unTc,tryAndReport,fio
             ,errF,report)
import IO
import List(partition,(\\),nub,find)
import Auxillary(plist,plistf,foldrM,backspace,Loc(..),extendL,DispInfo)
import SCC(topSortR)
import Monad(when)
import Infer2
import RankN(pprint)
import NarrowMod(narrow,showStep)
import System(getArgs)
import Data.Map(Map,toList)
import Directory
import Char(isAlpha,isDigit)
import System.IO(hClose)
import Monads(handleP)
import Manual(makeManual)
import Commands

import System.Console.Readline(setCompletionEntryFunction)
-- setCompletionEntryFunction :: Maybe (String -> IO [String]) -> IO ()

-------------------------------------------------------------
-- The programmer interface: the top level loop.
-- it performs the read-eval-typecheck-print loop.
-- It catches exceptions, and ties all the other pieces together.

----------------------------------------------
-- Perform one Read-Eval-Print action.

-- readEvalPrint :: [String] -> (TcEnv) -> FIO(TcEnv)
readEvalPrint commandTable sources tenv =
  do { let tabExpandFun = completionEntry tenv
     ; input <- lineEditReadln "prompt> " tabExpandFun
     ; z <- parseString pCommand input
     ; case z of
        Left s -> do {writeln s; return (tenv) }
        Right(x,rest) ->
         case x of
          (ColonCom com str) -> dispatchColon commandTable tenv com str
          (ExecCom e) -> execExp tenv e
          (DrawCom p e) -> drawPatExp tenv p e
          (LetCom d) -> letDec elabDs tenv d
     }


-- Repeat Read-Eval-Print until the :q command is given
topLoop commandTable sources env = tryAndReport
  (do { fio(hFlush stdout)
      ; env' <-  (readEvalPrint commandTable sources env)
      ; topLoop commandTable sources env'
      }) (report (topLoop commandTable sources env))

------------------------------------------------------------------
-- Commands for load files, then going into the Toplevel loop
------------------------------------------------------------------

-- load just the prelude and then go into the toplevel loop
main :: IO ()
main = runFIO(do { writeln "loading the prelude (LangPrelude.prg)"
                 ; fio $ hSetBuffering stdout NoBuffering
                 ; fio $ hSetBuffering stdin  NoBuffering
                 ; env1 <- tryAndReport (elabFile "LangPrelude.prg" initTcEnv)
                             (report (return initTcEnv))
                 ; let sources = ["LangPrelude.prg"]
                 ; topLoop (commandF sources elabFile) sources env1
                 ; return () }) errF


-- load the prelude and then load the file "s", and then go into the toplevel loop.
go :: String -> IO ()
go s =
  runFIO(do { writeln (version++"  --  Type ':?' for command line help."++"\n\n")
            ; writeln "loading the prelude (LangPrelude.prg)"
            ; env <- tryAndReport (elabFile "LangPrelude.prg" initTcEnv)
                            (report (return initTcEnv))
            ; env2 <- elabFile s env
            ; let sources = [s,"LangPrelude.prg"]
            ; topLoop (commandF sources elabFile) sources env2
            ; return () }) errF


-- Don't load the prelude, just load "s" then go into the toplevel loop.
run :: String -> IO ()
run s = runFIO(do { writeln ("loading "++s)
                  ; env1 <- tryAndReport (elabFile s initTcEnv)
                                         (report (return initTcEnv))
                  ; topLoop (commandF [s] elabFile) [s] env1
                  ; return () }) errF


-- Try to load a file, if it fails for any reason, exit the program
-- with an unrecoverable error. Used in testing, where failure means
-- a major error, something very bad (and unexpected), has happened
try_to_load s =
   runFIO(do { writeln ("loading "++s)
             ; env1 <- tryAndReport (elabFile s initTcEnv) err2
             ; writeln (s++" successfully loaded")
             ; return () }) errF
  where err2 loc disp mess = error ("At "++show loc++"\n"++mess)


-- Get the file to "run" from the command line arguments, then "run" it
omega :: IO()
omega =
  do { args <- getArgs
     ; putStr (version++"\n")
     ; putStr ("Build Date: "++buildtime++"\n\n")
     ; putStr "Type ':?' for command line help.\n"
     ; case args of
        [] -> run "LangPrelude.prg"
        ("-tests" :_ ) -> alltests
        ("-prim" : _) -> makeManual
        (_ : _) -> let arg1 = head args
                   in if arg1=="-tests"
                         then alltests
                         else run arg1
     }

-------------------------------------------------------------------------------
-- elabDs is the interface to everything. Elaborates a mutually recursive [Dec]
-- other functions read the [Dec] from files and call this function

elabDs :: [Dec] -> TcEnv -> FIO TcEnv
elabDs ds (tenv) =
  do { let nam (Global s) = s
     ; write ((display (map nam (concat (map decname ds))))++" ")
     ; (tenv1,ds1,cs1) <- checkDecs tenv ds   -- type check the list
     --; mapM (writeln .show) ds
     --; mapM (writeln . show) ds1
     ; when (not (null cs1)) (fail ("2 Unsolved constraints: "++show cs1))
     ; env1 <- elaborate None ds1 (runtime_env tenv)  -- evaluate the list
     ; return(tenv1 { runtime_env = env1 })
     }

display [s] = s
display ss = plistf id "(" ss " " ")"


------------------------------------------------------------
-- Read a [Dec] from a file, then split it into imports and
-- binding groups, uses elabDs to do the work.

elabFile :: String -> (TcEnv) -> FIO(TcEnv)
elabFile file (tenv) =
   do { all <- parseDecs file
      ; let (imports,ds) = partition importP all
            (dss,pairs) = topSortR freeOfDec ds
      --; writeln (show(map freeOfDec ds))
      ; tenv2 <- importManyFiles imports tenv
      -- Check for multiple definitions in the file
      ; multDef ds (concat (map fst pairs))
      -- Check if any names are already declared
      ; mapM (notDup tenv file) (foldr (\ (exs,deps) ss -> exs++ss) [] pairs)
      ; tenv3 <- foldF elabDs (tenv2) dss
      ; writeln ("\n File "++file++" loaded.\n")
      ; return tenv3
      }



------------------------------------------------------------------
-- Get a [Dec] from a file name

parseDecs :: String -> FIO[Dec]
parseDecs file =
  do { hndl <- fio (openFile file ReadMode)
     ; let err disp mess = fio((hClose hndl) >> fail mess)
           -- if parsing fails, we should close the file
     ; x <- handleP (const True) 10
                    (fio (parseHandle program file hndl)) err
     ; fio(hClose hndl)
     ; case x of
        Left s -> fail s
        Right(Program ds) -> return ds   -- mapM gadt2Data ds
     }



-------------------------------------------------------------------------
-- Omega has a very simple importing mechanism. A user writes:
-- import "xx.prg" (f,g,T)
-- to import the file named "xx.prg", all symbols with names "f", "g", "T"
-- (no matter what namespace they appear in) are imported into the
-- current environment. Usually "xx.prg" is a complete path as Omega's
-- notion of current directory is quite primitive.

importP (Import s vs) = True
importP _ = False

importManyFiles [] tenv = return tenv
importManyFiles (d:ds) tenv =
  do { next <- importFile d tenv; importManyFiles ds next }

importFile :: Dec -> TcEnv -> FIO TcEnv
importFile (Import name vs) tenv =
  case lookup name (imports tenv) of
     Just previous -> return tenv
     Nothing -> do { new <- elabFile name initTcEnv
                   ; return(importNames name vs new tenv) }

importNames :: String -> [Var] -> TcEnv -> TcEnv -> TcEnv
importNames name vs new old =
  old { imports = (name,new):(imports old)
      , var_env = addListToFM (var_env old) (filter p (toList (var_env new)))
      , type_env = (filter q (type_env new)) ++ (type_env old)
      , runtime_env = add (runtime_env new) (runtime_env old)
      , rules = appendFM2 (rules old) (filter p2 (toList (rules new)))
      }
 where p (x,y) = elem x vs
       p2 (s,y) = elem (Global s) vs
       q (str,tau,polyk) = elem (Global str) vs
       add (Ev xs _) (Ev ys t) = Ev (filter p xs ++ ys) t




multDef :: [Dec] -> [Var] -> FIO ()
multDef ds names = if null dups then return () else fail (foldr report "" dups)
  where dups = nub(names \\ nub names)
        locs = concat(map decloc ds)
        report :: Var -> String -> String
        report nm s = show nm ++ " is multiply defined at lines "++show (foldr acc [] locs)++"\n"++s
            where acc (name,SrcLoc line col) ls = if nm==name then line:ls else ls
                  acc (name,Z) ls = ls

-----------------------------------------------------
-- this command is for the maintainers of Omega, it trys
-- to load all the files in the TestPrograms directory with
-- extension ".prg"   It is used to exercise Omega.

alltests =
  do { setCurrentDirectory "./TestPrograms"
     ; files <- getDirectoryContents "."
     ; let ok x = case reverse x of { ('g':'r':'p':'.':_) -> True; _ -> False}
     ; print (filter ok files)
     ; mapM try_to_load (filter ok files)
     ; setCurrentDirectory ".."
     }


-------------------------------------------------------------------------------
------------------------------------------------------------------
-- Some shortcuts to running the interpreter

work = run "work.prg"
circ = run "Examples/RecursiveCircuit.prg"
parse = run "Examples/Parser.prg"

tests = go "tests.prg"

tm = go "toMetaMl.prg"

q s = go ("C:/tmp/OmegaExamples/"++s++".prg")
