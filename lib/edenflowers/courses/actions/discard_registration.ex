defmodule Edenflowers.Courses.Actions.DiscardRegistration do
  @moduledoc "Discards unpaid checkout data, returning the current registration when a payment needs it."
  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Changes.StaleRecord
  alias Ash.Error.Invalid
  alias Ash.Error.Query.NotFound
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Payments.Errors.PaymentInProgress

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)
    read_opts = Keyword.merge(opts, load: [:committed?], not_found_error?: false)

    with {:ok, %{committed?: false} = registration} <- Ash.get(input.resource, input.arguments.id, read_opts) do
      discard(registration, opts, read_opts)
    end
  end

  defp discard(registration, opts, read_opts) do
    case Ash.destroy(registration, Keyword.put(opts, :action, :discard)) do
      :ok ->
        {:ok, nil}

      {:error, %Invalid{errors: errors}} = failure ->
        if errors != [] and Enum.all?(errors, &retention?/1),
          do: Ash.get(CourseRegistration, registration.id, read_opts),
          else: failure

      {:error, error} ->
        {:error, error}
    end
  end

  defp retention?(%PaymentInProgress{}), do: true
  defp retention?(%StaleRecord{resource: CourseRegistration}), do: true
  defp retention?(%NotFound{resource: CourseRegistration}), do: true
  defp retention?(_error), do: false
end
