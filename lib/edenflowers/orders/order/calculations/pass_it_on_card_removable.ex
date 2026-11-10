defmodule Edenflowers.Orders.Order.Calculations.PassItOnCardRemovable do
  @moduledoc """
  Whether Jennie can remove the gift's pass-it-on card, if she typed the wrong
  code: the gift is still to deliver and its recipient hasn't opened the card.

  Computed in Elixir from the already-loaded card so the SQL doesn't inline the
  changeable and card-eligibility expressions again.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context),
    do: [:pass_it_on_card_changeable?, pass_it_on_card: [:gift_order_linkable?]]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      record.pass_it_on_card_changeable? and
        match?(%{gift_order_linkable?: true}, record.pass_it_on_card)
    end)
  end
end
