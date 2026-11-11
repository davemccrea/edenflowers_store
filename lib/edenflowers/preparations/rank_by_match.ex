defmodule Edenflowers.Preparations.RankByMatch do
  @moduledoc """
  Puts a search's closest matches first: sorts by the resource's `match_rank` calculation for the
  action's `term` argument, and loads it so a caller can compare results across resources. Place it
  before the action's own sort, which then orders equally close matches. Does nothing without a term.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :term) do
      nil ->
        query

      term ->
        query
        |> Ash.Query.sort(match_rank: {%{term: term}, :asc})
        |> Ash.Query.load(match_rank: %{term: term})
    end
  end
end
