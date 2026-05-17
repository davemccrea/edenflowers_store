defmodule Edenflowers.Weekday do
  @moduledoc """
  Maps `Date.day_of_week/1` integers to atoms used by `FulfillmentOption.available_days`.
  """

  @typedoc "Day-of-week atom matching the values stored in `FulfillmentOption.available_days`."
  @type t :: :monday | :tuesday | :wednesday | :thursday | :friday | :saturday | :sunday

  @spec from_date(Date.t()) :: t()
  def from_date(%Date{} = date), do: from_integer(Date.day_of_week(date))

  @spec from_integer(1..7) :: t()
  def from_integer(1), do: :monday
  def from_integer(2), do: :tuesday
  def from_integer(3), do: :wednesday
  def from_integer(4), do: :thursday
  def from_integer(5), do: :friday
  def from_integer(6), do: :saturday
  def from_integer(7), do: :sunday

  @spec to_integer(t()) :: 1..7
  def to_integer(:monday), do: 1
  def to_integer(:tuesday), do: 2
  def to_integer(:wednesday), do: 3
  def to_integer(:thursday), do: 4
  def to_integer(:friday), do: 5
  def to_integer(:saturday), do: 6
  def to_integer(:sunday), do: 7
end
