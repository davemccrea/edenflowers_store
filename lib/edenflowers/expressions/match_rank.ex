defmodule Edenflowers.Expressions.MatchRank do
  @moduledoc """
  `match_rank(text, term)` in an Ash expression: how well a search term matches a text, ignoring
  case. 0 when the text is the term, 1 when the text or one of its words starts with it, 2 when it
  appears anywhere else, and 3 when it doesn't appear or the text is nil. Lower is better. A hyphen
  starts a word like a space does, so "karin" starts a word in "Anna-Karin".
  """
  use Ash.CustomExpression, name: :match_rank, arguments: [[:string, :string], [:ci_string, :ci_string]]

  def expression(AshPostgres.DataLayer, [text, term]) do
    {:ok,
     expr(
       fragment(
         """
         CASE
           WHEN lower(?::text) = lower(?::text) THEN 0
           WHEN strpos(' ' || translate(lower(?::text), '-', ' '), ' ' || translate(lower(?::text), '-', ' ')) > 0 THEN 1
           WHEN strpos(lower(?::text), lower(?::text)) > 0 THEN 2
           ELSE 3
         END
         """,
         ^text,
         ^term,
         ^text,
         ^term,
         ^text,
         ^term
       )
     )}
  end

  def expression(_data_layer, _arguments), do: :unknown
end
