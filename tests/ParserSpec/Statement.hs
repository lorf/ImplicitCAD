-- Implicit CAD. Copyright (C) 2011, Christopher Olah (chris@colah.ca)
-- Copyright (C) 2014-2017, Julia Longtin (julial@turinglace.com)
-- Released under the GNU AGPLV3+, see LICENSE

-- | Statement related hspec tests.
module ParserSpec.Statement (statementSpec) where

import Prelude (String, Maybe(Just), Bool(True), ($))

import Test.Hspec (Spec, Expectation, shouldBe, shouldSatisfy, it, pendingWith, describe)

import ParserSpec.Util (bool, num, minus, mult, index)

import Graphics.Implicit.ExtOpenScad.Definitions (StatementI(StatementI), Symbol, Expr(ListE, LamE, Var), Statement(NewModule, ModuleCall, If, (:=)), Pattern(Name, ListP))

-- Parse an ExtOpenScad program.
import Graphics.Implicit.ExtOpenScad.Parser.Statement (parseProgram)

import Data.Either (Either(Right), isLeft)

import Text.ParserCombinators.Parsec (Line, Column)

-- | an expectation that a string is equivalent to a statement.
infixr 1 -->
(-->) :: String -> [StatementI] -> Expectation
(-->) source stmts =
    parseProgram source `shouldBe` Right stmts

-- | an expectation that a string generates an error.
parsesAsError :: String -> Expectation
parsesAsError source = parseProgram  source `shouldSatisfy` isLeft

-- | A single statement.
single :: Statement StatementI -> [StatementI]
single st = [StatementI 1 1 st]

-- | A function call.
call :: Symbol -> Column -> [(Maybe Symbol, Expr)] -> [StatementI] -> StatementI
call name position args stmts = StatementI 1 position (ModuleCall name args stmts)

-- | Test a simple if block.
ifSpec :: Spec
ifSpec = it "parses" $
    "if (true) { a(); } else { b(); }" -->
      single ( If (bool True) [call "a" 13 [] []] [call "b" 27 [] []])

-- | Test assignments.
assignmentSpec :: Spec
assignmentSpec = do
  it "parses correctly" $
    "y = -5;" --> single ( Name "y" := num (-5))
  it "handles pattern matching" $
    "[x, y] = [1, 2];" --> single (ListP [Name "x", Name "y"] := ListE [num 1, num 2])
  it "handles the function keyword and definitions" $
    "function foo(x, y) = x * y;" --> single fooFunction
  it "handles nested indexing" $
    "x = [y[0] - z * 2];" -->
    single ( Name "x" := ListE [minus [index [Var "y", num 0],
                                           mult [Var "z", num 2]]])
  where
    fooFunction :: Statement st
    fooFunction = Name "foo" := LamE [Name "x", Name "y"]
                                (mult [Var "x", Var "y"])

-- | the parser fails on as empty file. This can't be right.
emptyFileIssue :: Expectation -> Expectation
emptyFileIssue _ = pendingWith "parser should probably allow empty files"

-- | Our entry points. Test all of the statements.
statementSpec :: Spec
statementSpec = do
  describe "empty file" $
    it "returns an empty list" $
      emptyFileIssue $ "" --> []
  describe "assignment" assignmentSpec
  describe "if" ifSpec
  describe "line comment" $
    it "parses as empty" $ emptyFileIssue $ "// foish bar\n" --> []
  describe "module call" $
    it "parses" $ "foo();" --> single (ModuleCall "foo" [] [])
  describe "difference of two cylinders" $
    it "parses correctly" $
      "difference(){ cylinder(r=5,h=20); cylinder(r=2,h=20); }"
      --> single (
        ModuleCall "difference" [] [
           call "cylinder" 15 [(Just "r", num 5.0),
                             (Just "h", num 20.0)]
            [],
           call "cylinder" 35 [(Just "r", num 2.0),
                             (Just "h", num 20.0)]
            []])
  describe "empty module definition" $
    it "parses correctly" $
      "module foo_bar() {}" --> single (NewModule "foo_bar" [] [])


