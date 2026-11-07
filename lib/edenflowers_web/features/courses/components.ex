defmodule EdenflowersWeb.Courses.Components do
  @moduledoc """
  Photo attribution shared by the course list and detail page.
  """
  use EdenflowersWeb, :html

  attr :course, :map, required: true

  def photo_credit(assigns) do
    ~H"""
    {~t"Photo:"}
    <a
      :if={@course.photo_credit_url}
      href={photo_credit_url(@course.photo_credit_url)}
      target="_blank"
      rel="noopener noreferrer"
      class="link-underline-static-body break-words"
    >
      {@course.photo_credit_name}
    </a>
    <span :if={!@course.photo_credit_url} class="break-words">{@course.photo_credit_name}</span>
    """
  end
end
