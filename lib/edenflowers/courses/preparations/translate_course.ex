defmodule Edenflowers.Courses.Preparations.TranslateCourse do
  @moduledoc "Loads each booking's course in the booking's own locale, for emailing its customer."
  use Ash.Resource.Preparation

  alias Edenflowers.Translations

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn _query, registrations ->
      {:ok, Enum.map(registrations, &translate_course/1)}
    end)
  end

  defp translate_course(registration) do
    registration = Ash.load!(registration, :course, authorize?: false)
    Map.update!(registration, :course, &Translations.translate(&1, String.to_existing_atom(registration.locale)))
  end
end
