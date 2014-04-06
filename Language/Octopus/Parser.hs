{-| Parse Octopus source code. The Octopus grammar is:


> file ::= ('export' <expr>)? <stmt>*
> stmt ::= <expr> | _field_ <expr> | 'open' <expr>
> expr ::= <atom> | <list> | <object>
>       |  <combination> | <block> | <quotation>
>       |  <accessor> | <mutator>
>       | '(' <expr> ')' |  /\.<expr>/
> 
> atom ::= _symbol_ | _number_ | _string_ | _heredoc_ | _primitive_
> list ::= '[' (<expr>+ (',' <expr>+)*)? ']'
> object ::= '{' (_field_ <expr>+ (',' _field_ <expr>+)*)? '}'
> combination ::= '(' <expr> <expr>+ ')'
> block ::= 'do' <stmt>+ ';'
> accessor ::= /@<name>/ | /:<name>/
> mutator ::= '@(' _field_ <expr>+ ')' | ':(' _field_ <expr>+ ')'
> quotation ::= /`<expr>/
> 
> symbol ::= _name_ - reserved
>     reserved = {'do', 'letrec', 'export', 'open'}
> primitive ::= /#<[a-zA-Z]+>/
> field ::= /<name>:/
> number ::= /[+-]?(0[xX]<hexnum>|0[oO]<octnum>|0[bB]<binnum>|<decnum>)/
>     decnum ::= /\d+(\.\d+<exponent>?|\/\d+)?/
>     hexnum ::= /\x+(\.\x+([hH][+-]?\x+)?|\/\x+)?/
>     octnum ::= /[0-7]+(\.[0-7]+<exponent>?|\/[0-7]+)?/
>     binnum ::= /[01]+(\.[01]+<exponent>?|\/[01]+)?/
>     exponent ::= /[eE][+-]?\d+|[hH][+-]?\x+/
> string ::= /"([^"\\]|\\[abefntv'"&\\]|\\<numescape>|\\\s*\n\s*\\)*"/
>     numescape ::= /[oO][0-7]{3}|[xX]\x{2}|u\x{4}|U0\x{5}|U10x{4}/
> heredoc ::= /#<<(?'END'\w+)\n.*?\n\g{END}>>(\n|$)/
> name ::= /<namehead><nametail>|-<namehead><nametail>|-(-<nametail>)?/
>     namehead = /[^#\\"`()[]{}@:;.,0-9-]/
>     nametail = /[^#\\"`()[]{}@:;.,]*/
> 
> linecomment ::= /#(?!<)\.*?\n/
> blockcomment ::= /#\{([^#}]+|<blockcomment>|#[^{]|\}[^#])*\}#/

-}
module Language.Octopus.Parser where

import Import

import qualified Data.ByteString.Lazy as BS
import qualified Data.Text as T
import Text.Parsec ( Parsec, SourceName, ParseError
                   , try, (<?>), unexpected, parserZero
                   , char, anyChar, eof)
import qualified Text.Parsec as P
import Language.Parse
import Language.Desugar

import Language.Octopus.Data
import Language.Octopus.Data.Shortcut
import Language.Octopus.Basis
import Language.Octopus.Parser.Preprocess


type Parser = Parsec String ()
type Directive = String

parseOctopusExpr :: SourceName -> String -> Either ParseError Val
parseOctopusExpr sourceName input = desugar <$> P.runParser (padded expr <* padded eof) () sourceName input

parseOctopusFile :: SourceName -> String -> Either ParseError ([Directive], Val)
parseOctopusFile sourceName input =
    let (directives, code) = partitionCode input
    in (,) directives <$> P.runParser octopusFile () sourceName code
    where
    octopusFile = do
        es <- P.many $ desugarStatement <$> padded statement
        padded eof
        return $ loop es
    loop [] = mkCall getenv (mkOb [])
    loop (Defn s:rest) = mkCall (mkDefn s) (loop rest)
    loop (Open e:rest) = mkCall (mkOpen e) (loop rest)
    loop (Expr e:rest) = mkCall (mkExpr e) (loop rest)
    getenv = (mkCall (Pr Vau) (mkSq [mkSq [mkSy "e", mkOb []], mkSy "e"]))

define :: Parser (Defn Syx)
define = do
    var <- try (expr <* char ':' <* whitespace)
    body <- expr
    return (var, body)

letrec :: Parser (Defn Syx)
letrec = do
    try $ string "letrec" <* whitespace
    var <- try (expr <* char ':' <* whitespace)
    body <- expr
    return (var, body)    

open :: Parser Syx
open = do
    try $ string "open" *> whitespace
    expr

expr :: Parser Syx
expr = composite P.<|> atom
    where
    atom = Lit <$> P.choice [symbol, numberLit, textLit, heredoc, primitive] <?> "atom"
    composite = P.choice [ block, combine, sq, ob, quote, dottedExpr
                         , accessor, mutator, infixAccessor, infixMutator]

statement :: Parser (Statement Syx)
statement = P.choice [ Defn <$> define
                     , LRec <$> letrec
                     , Open <$> open
                     , Expr <$> expr
                     ]


------ Sugar ------
data Statement a = Defn (Defn a)
                 | LRec (Defn a)
                 | Expr a
                 | Open a
                 | Deco a
    deriving (Show)
type Defn a = (a, a)
data Syx = Lit Val
         | Call [Syx]
         | SqSyx [Syx]
         | ObExpr [(Symbol, Syx)]
         | Do [Statement Syx]
         | Infix Syx
    deriving (Show)

desugar :: Syx -> Val
desugar (Lit x) = x
desugar (Call [x]) = desugar x
desugar (Call xs) = loop . (desugar <$>) $ revTripBy isInfix (id, rewrite) xs
    where
    rewrite [] inf rest = error "TODO syntax error: infix :/. needs a subject"
    rewrite subject (Infix inf) rest = inf : Call subject : rest
    loop [e] = e
    loop [f, x] = mkCall f x
    loop es = mkCall (loop $ init es) (last es)
    isInfix (Infix _) = True
    isInfix _ = False
desugar (SqSyx xs) = mkSq $ desugar <$> xs
desugar (ObExpr xs) = mkOb $ desugarField <$> xs
desugar (Do xs) = loop xs
    where
    loop [Defn d]      = mkCall (mkDefn $ desugarDefine d) (mkOb [])
    loop [Expr e]      = desugar e
    loop (Defn d:rest) = mkCall (mkDefn $ desugarDefine d) (loop rest)
    loop (LRec d:rest) = mkCall (mkDefn $ desugarLetrec d) (loop rest)
    loop (Open e:rest) = mkCall (mkOpen $ desugar e) (loop rest)
    loop (Expr e:rest) = mkCall (mkExpr $ desugar e) (loop rest)
desugar x = error $ "INTERNAL ERROR Octopus.Parser.desugar: " ++ show x

desugarField :: (Symbol, Syx) -> (Symbol, Val)
desugarField (k, e) = (k, desugar e)

desugarDefine :: Defn Syx -> (Val, Val)
desugarDefine (x, e) = (desugar x, desugar e)

desugarLetrec :: Defn Syx -> (Val, Val)
desugarLetrec (x, e) = let f = desugar x
                       in (f, mkCall (mkSy "__Y__") (mkCall (mkCall (mkSy "__lambda__") f) (desugar e)))

desugarStatement :: Statement Syx -> Statement Val
desugarStatement (Defn d) = Defn (desugarDefine d)
desugarStatement (LRec d) = Defn (desugarLetrec d)
desugarStatement (Expr e) = Expr (desugar e)
desugarStatement (Open e) = Open (desugar e)
desugarStatement (Deco f) = Deco (desugar f)


------ Atoms ------
primitive :: Parser Val
primitive = P.choice (map mkPrimParser table)
    where
    mkPrimParser (name, val) = string ("#<" ++ name ++ ">") >> return val
    table = [ ("vau", Pr Vau), ("eval", Pr Eval), ("match", Pr Match), ("ifz!", Pr Ifz), ("import", Pr Imp)
            , ("eq", Pr Eq), ("neq", Pr Neq), ("lt", Pr Lt), ("lte", Pr Lte), ("gt", Pr Gt), ("gte", Pr Gte)
            , ("add", Pr Add) , ("mul", Pr Mul) , ("sub", Pr Sub) , ("div", Pr Div)
            , ("numer", Pr Numer) , ("denom", Pr Denom) , ("numParts", Pr NumParts)
            , ("openFile", Pr OpenFp), ("flush", Pr FlushFp), ("close", Pr CloseFp)
            , ("readByte", Pr ReadFp), ("writeByte", Pr WriteFp)
            , ("mkTag", Pr MkTag)
            , ("len", Pr Len) , ("cat", Pr Cat) , ("cut", Pr Cut)
            , ("extends", Pr Extends) , ("del", Pr Delete) , ("keys", Pr Keys) , ("get", Pr Get)
            , ("handle", Pr Handle) , ("raise", Pr Raise)

            , ("stdin", fpStdin), ("stdout", fpStdout), ("stdin", fpStderr)
            , ("IOError", exnIOError)
            ]

symbol :: Parser Val
symbol = do
    n <- name
    when (n `elem` ["do", "letrec", "export", "open"])
        (unexpected $ "reserved word (" ++ n ++ ")") --FIXME report error position before token, not after
    return $ mkSy n

numberLit :: Parser Val
numberLit = Nm <$> anyNumber

--TODO maybe bytes literals

textLit :: Parser Val
textLit = do
    content <- catMaybes <$> between2 (char '\"') (P.many maybeLiteralChar)
    return $ mkTx content

heredoc :: Parser Val
heredoc = do
    string "#<<"
    end <- P.many1 P.letter <* char '\n'
    let endParser = char '\n' *> P.string (end ++ ">>") <* (void (char '\n') P.<|> eof)
    mkTx <$> anyChar `manyThru` endParser


------ Composites ------
combine :: Parser Syx
combine = do
    postPadded $ char '('
    e <- bareCombination
    padded $ char ')'
    return e

sq :: Parser Syx
sq = do
    postPadded $ char '['
    elems <- bareCombination `P.sepBy` padded comma
    padded $ char ']'
    return $ SqSyx elems

ob :: Parser Syx
ob = do
    postPadded $ char '{'
    elems <- pair `P.sepBy` padded comma
    padded $ char '}'
    return $ ObExpr elems
    where
    pair = do
        key <- intern <$> padded name
        char ':' <* whitespace
        val <- bareCombination
        return (key, val)

block :: Parser Syx
block = do
        try $ string "do" >> whitespace
        states <- P.many1 $ postPadded statement
        char ';'
        return $ Do states

quote :: Parser Syx
quote = do
    char '`'
    e <- expr
    return $ Call [Lit $ mkSy "__quote__", e]

dottedExpr :: Parser Syx
dottedExpr = Infix <$> (char '.' *> expr)

accessor :: Parser Syx
accessor = do
    key <- try $ char '@' *> name
    return $ Call [Lit $ mkSy "__get__", Lit $ mkSy key]

mutator :: Parser Syx
mutator = do
    string "@("
    key <- name <* char ':' <* whitespace
    e <- bareCombination
    char ')'
    return $ Call [Lit $ mkSy "__modify__", Lit $ mkSy key, e]

infixAccessor :: Parser Syx
infixAccessor = do
    key <- try $ char ':' *> name
    return . Infix $ Call [Lit $ mkSy "__get__", Lit $ mkSy key]

infixMutator :: Parser Syx
infixMutator = do
    string ":("
    key <- name <* char ':' <* whitespace
    e <- bareCombination 
    char ')'
    return . Infix $ Call [Lit $ mkSy "__modify__", Lit $ mkSy key, e]


------ Space ------
whitespace :: Parser ()
whitespace = (<?> "space") . P.skipMany1 $ P.choice [spaces1, lineComment, blockComment]

lineComment :: Parser ()
lineComment = void $ do
    try $ char '#' >> P.notFollowedBy (char '<')
    anyChar `manyThru` (void (char '\n') P.<|> eof)

blockComment :: Parser ()
blockComment = parserZero

padded :: Parser a -> Parser a
padded p = try $ P.optional whitespace >> p
postPadded :: Parser a -> Parser a
postPadded p = p <* P.optional whitespace


------ Helpers ------
name :: Parser String
name = P.choice [ (:) <$> namehead <*> nametail
                , (:) <$> char '-' <*> P.option [] ((:) <$> (namehead P.<|> char '-') <*> nametail)
                ]
    where
    namehead = blacklistChar (`elem` reservedFirstChar)
    nametail = P.many $ blacklistChar (`elem` reservedChar)
    reservedChar = "#\\\"`()[]{}@:;.,"
    reservedFirstChar = reservedChar ++ "-0123456789"

comma :: Parser ()
comma = char ',' >> whitespace

bareCombination :: Parser Syx
bareCombination = do
    es <- P.many1 (postPadded expr)
    return $ case es of { [e] -> e; es -> Call es }

mkDefn (x, val) = mkCall (mkCall (mkSy "__let__") x) val
mkOpen env = mkCall (mkSy "__open__") env
mkExpr e = mkCall (mkCall (mkSy "__let__") (mkOb [])) e



