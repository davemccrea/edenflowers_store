defmodule EdenflowersWeb.Admin.CinderTheme do
  @moduledoc """
  Cinder table theme for the admin.

  Extends the stock `daisy_ui` theme but remaps the filter-panel header away
  from DaisyUI's `card-title` class. The storefront redefines `card-title` as a
  large serif heading (see `assets/css/app.css`), which the admin's sans-serif,
  operational register should not inherit.
  """
  use Cinder.Theme

  extends :daisy_ui

  set :filter_header_class, "flex items-center justify-between mb-4"
  set :filter_title_class, "flex items-center gap-2 text-base font-semibold text-base-content"
  set :filter_count_class, "badge badge-primary badge-sm tabular-nums"
end
