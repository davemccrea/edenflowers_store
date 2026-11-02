defmodule Edenflowers.Slug.CurrentSlug do
  @moduledoc """
  Where an outdated link should go: the current slug of the record whose id or
  former slug the `param` argument is, or nil when it is neither, such as a
  current slug. Takes the same `former_slugs` and `owner_key` options as
  `Edenflowers.Slug.SetSlug`.
  """
  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, opts, _context) do
    param = input.arguments.param

    record =
      case uuid(param) do
        {:ok, id} ->
          Ash.get!(input.resource, id, error?: false, authorize?: false)

        :error ->
          case Ash.read_one!(Ash.Query.filter_input(opts[:former_slugs], slug: param), authorize?: false) do
            nil -> nil
            former -> Ash.get!(input.resource, Map.fetch!(former, opts[:owner_key]), authorize?: false)
          end
      end

    {:ok, record && record.slug}
  end

  # Only the written-out form: Ecto.UUID.cast/1 also takes any 16-byte string, like "spring-workshops".
  defp uuid(param) when byte_size(param) == 36, do: Ecto.UUID.cast(param)
  defp uuid(_param), do: :error
end
