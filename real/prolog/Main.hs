--
-- Prolog interpreter top level module
-- Mark P. Jones November 1990
--
-- uses Haskell B. version 0.99.3
--
module Main(main) where

import PrologData
import Parse
import Interact
import Subst
import Engine
import Version
import Data.List(nub)--1.3

import Control.Monad
import Data.Char
import System.Environment
import System.IO.Error (catchIOError)

--- Command structure and parsing:

data Command = Fact Clause | Query [Term] | Show | Error | Quit | NoChange

command :: Parser Command
command  = just (sptok "bye" `orelse` sptok "quit") `doo` (\quit->Quit)
               `orelse`
           just (okay NoChange)
               `orelse`
           just (sptok "??") `doo` (\show->Show)
               `orelse`
           just clause `doo` Fact
               `orelse`
           just (sptok "?-" `seQ` termlist) `doo` (\(q,ts)->Query ts)
               `orelse`
           okay Error

--- Main program read-solve-print loop:

signOn           :: String
signOn            = "Mini Prolog Version 1.5 (" ++ version ++ ")\n\n"

main              = --echo False abort
                    putStr signOn >>
                    putStr ("Reading " ++ stdlib) >>
                    catchIOError (readFile stdlib)
                      (\fail -> putStr "...not found\n" >> return "")
		      >>= \ is ->
		    if null is then
		       interpreter []
		    else
                      let parse   = map clause (lines is)
                          clauses = [ r | ((r,""):_) <- parse ]
                          reading = ['.'| c <- clauses] ++ "done\n"
                      in
                      putStr reading >>
                      interpreter clauses

stdlib           :: String
stdlib            = "runtime_files/stdlib"

-- | Using @salt xs@ on an loop-invariant @xs@ inside a loop prevents the
-- compiler from floating out the input parameter.
salt :: [a] -> IO [a]
salt xs = do
  s <- length <$> getArgs
  -- Invariant: There are less than 'maxBound' parameters passed to the
  --            executable, otherwise this isn't really @pure . id@
  --            anymore.
  pure (take (max (maxBound - 1) s) xs)

hash :: String -> Int
hash = foldr (\c acc -> ord c + acc*31) 0

interpreter      :: [Clause] -> IO ()
interpreter lib   = do
  let startDb = foldl addClause emptyDb lib
  is <- getContents
  replicateM_ 200 $ do
    is' <- salt is
    print (hash (loop startDb is'))

loop             :: Database -> String -> String
loop db           = readln "> " (exec db . fst . head . command)

exec             :: Database -> Command -> String -> String
exec db (Fact r)  = skip                              (loop (addClause db r))
exec db (Query q) = demonstrate db q
exec db Show      = writeln (show db)                 (loop db)
exec db Error     = writeln "I don't understand\n"    (loop db)
exec db Quit      = writeln "Thank you and goodbye\n" end
exec db NoChange  = skip                              (loop db)

--- Handle printing of solutions etc...

solution      :: [Id] -> Subst -> [String]
solution vs s  = [ show (Var i) ++ " = " ++ show v
                                | (i,v) <- [ (i,s i) | i<-vs ], v /= Var i ]

demonstrate     :: Database -> [Term] -> Interactive
demonstrate db q = printOut (map (solution vs) (prove db q))
 where vs               = (nub . concat . map varsIn) q
       printOut []      = writeln "no.\n"     (loop db)
       printOut ([]:bs) = writeln "yes.\n"    (loop db)
       printOut (b:bs)  = writeln (doLines b) (nextReqd bs)
       doLines          = foldr1 (\xs ys -> xs ++ "\n" ++ ys)
       nextReqd bs      = writeln " "
                            (readch (\c->if c==';'
                                           then writeln ";\n" (printOut bs)
                                           else writeln "\n"  (loop db)) "")

--- End of Main.hs
