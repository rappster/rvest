#' Parse forms in a page.
#'
#' @export
#' @param x A node, node set or document.
#' @seealso HTML 4.01 form specification:
#'   \url{http://www.w3.org/TR/html401/interact/forms.html}
#' @examples
#' \donttest{
#' html_form(html("https://hadley.wufoo.com/forms/libraryrequire-quiz/"))
#' html_form(html("https://hadley.wufoo.com/forms/r-journal-submission/"))
#'
#' box_office <- html("http://www.boxofficemojo.com/movies/?id=ateam.htm")
#' box_office %>% html_node("form") %>% html_form()
#' }
html_form <- function(x) UseMethod("html_form")

#' @export
html_form.XMLAbstractDocument <- function(x) {
  html_form(html_nodes(x, "form"))
}

#' @export
html_form.XMLNodeSet <- function(x) {
  lapply(x, html_form)
}

#' @export
html_form.XMLInternalElementNode <- function(x) {
  stopifnot(inherits(x, "XMLAbstractNode"), XML::xmlName(x) == "form")

  attr <- as.list(XML::xmlAttrs(x))
  name <- attr$id %||% attr$name %||% "<unnamed>" # for human readers
  method <- toupper(attr$method) %||% "GET"
  enctype <- convert_enctype(attr$enctype)

  fields <- parse_fields(x)

  structure(
    list(
      name = name,
      method = method,
      url = attr$action,
      enctype = enctype,
      fields = fields
    ),
    class = "form")
}

convert_enctype <- function(x) {
  if (is.null(x)) return("form")
  if (x == "application/x-www-form-urlencoded") return("form")
  if (x == "multipart/form-data") return("multipart")

  warning("Unknown enctype (", x, "). Defaulting to form encoded.",
    call. = FALSE)
  "form"
}

#' @export
print.form <- function(x, indent = 0, ...) {
  cat("<form> '", x$name, "' (", x$method, " ", x$url, ")\n", sep = "")
  print(x$fields, indent = indent + 1)
}

#' @export
format.input <- function(x, ...) {
  if (x$type == "password") {
    value <- paste0(rep("*", nchar(x$value) %||% 0), collapse = "")
  } else {
    value <- x$value
  }
  paste0("<input ", x$type, "> '", x$name, "': ", value)
}

parse_fields <- function(form) {
  raw <- html_nodes(form, "input, select, textarea, button")

  fields <- lapply(raw, function(x) {
    switch(XML::xmlName(x),
      textarea = parse_textarea(x),
      input = parse_input(x),
      select = parse_select(x),
      button = parse_button(x)
    )
  })
  names(fields) <- pluck(fields, "name")
  class(fields) <- "fields"
  fields
}

#' @export
print.fields <- function(x, ..., indent = 0) {
  cat(format_list(x, indent = indent), "\n", sep = "")
}

# <input>: type, name, value, checked, maxlength, id, disabled, readonly, required
# Input types:
# * text/email/url/search
# * password: don't print
# * checkbox:
# * radio:
# * submit:
# * image: not supported
# * reset: ignored (client side only)
# * button: ignored (client side only)
# * hidden
# * file
# * number/range (min, max, step)
# * date/datetime/month/week/time
# * (if unknown treat as text)
parse_input <- function(input) {
  stopifnot(inherits(input, "XMLAbstractNode"), XML::xmlName(input) == "input")
  attr <- as.list(XML::xmlAttrs(input))

  structure(
    list(
      name = attr$name,
      type = attr$type %||% "text",
      value = attr$value,
      checked = attr$checked,
      disabled = attr$disabled,
      readonly = attr$readonly,
      required = attr$required %||% FALSE
    ),
    class = "input"
  )
}

parse_select <- function(select) {
  stopifnot(inherits(select, "XMLAbstractNode"), XML::xmlName(select) == "select")

  attr <- as.list(XML::xmlAttrs(select))
  options <- parse_options(html_nodes(select, "option"))

  structure(
    list(
      name = attr$name,
      value = options$value,
      options = options$options
    ),
    class = "select"
  )
}

#' @export
format.select <- function(x, ...) {
  paste0("<select> '", x$name, "' [", length(x$value), "/", length(x$options), "]")
}

parse_options <- function(options) {
  parse_option <- function(option) {
    attr <- as.list(XML::xmlAttrs(option))
    list(
      value = attr$value,
      name = XML::xmlValue(option),
      selected = !is.null(attr$selected)
    )
  }

  parsed <- lapply(options, parse_option)
  value <- pluck(parsed, "value", character(1))
  name <- pluck(parsed, "name", character(1))
  selected <- pluck(parsed, "selected", logical(1))

  list(
    value = value[selected],
    options = setNames(value, name)
  )
}

parse_textarea <- function(textarea) {
  attr <- as.list(XML::xmlAttrs(textarea))

  structure(
    list(
      name = attr$name,
      value = XML::xmlValue(textarea)
    ),
    class = "textarea"
  )
}

#' @export
format.textarea <- function(x, ...) {
  paste0("<textarea> '", x$name, "' [", nchar(x$value), " char]")
}

parse_button <- function(button) {
  stopifnot(inherits(button, "XMLAbstractNode"), XML::xmlName(button) == "button")
  attr <- as.list(XML::xmlAttrs(button))
  
  structure(
    list(
      name = attr$name %||% "<unnamed>",
      type = attr$type,
      value = attr$value,
      checked = attr$checked,
      disabled = attr$disabled,
      readonly = attr$readonly,
      required = attr$required %||% FALSE
    ),
    class = "button"
  )
}

#' @export
format.button <- function(x, ...) {
  paste0("<button ", x$type, "> '", x$name)
}


#' Set values in a form.
#'
#' @param form Form to modify
#' @param ... Name-value pairs giving fields to modify
#' @return An updated form object
#' @export
#' @examples
#' search <- html_form(html("https://www.google.com"))[[1]]
#' set_values(search, q = "My little pony")
#' set_values(search, hl = "fr")
#' \dontrun{set_values(search, btnI = "blah")}
set_values <- function(form, ...) {
  new_values <- list(...)

  # check for valid names
  no_match <- setdiff(names(new_values), names(form$fields))
  if (length(no_match) > 0) {
    stop("Unknown field names: ", paste(no_match, collapse = ", "),
      call. = FALSE)
  }

  for(field in names(new_values)) {
    type <- form$fields[[field]]$type %||% "non-input"
    if (type == "hidden") {
      warning("Setting value of hidden field '", field, "'.", call. = FALSE)
    } else if (type == "submit") {
      stop("Can't change value of submit input '", field, "'.", call. = FALSE)
    }

    form$fields[[field]]$value <- new_values[[field]]
  }

  form

}

#' Submit a form back to the server.
#'
#' @param session Session to submit form to.
#' @param form Form to submit
#' @param submit Name of submit button to use. If not supplied, defaults to
#'   first submission button on the form (with a message).
#' @param ... Additional arguments passed on to \code{\link[httr]{GET}()}
#'   or \code{\link[httr]{POST}()}
#' @return If successful, the parsed html response. Throws an error if http
#'   request fails. To access other elements of response, construct it yourself
#'   using the elements returned by \code{submit_request}.
#' @export
#' @examples
#' test <- google_form("1M9B8DsYNFyDjpwSK6ur_bZf8Rv_04ma3rmaaBiveoUI")
#' f0 <- html_form(test)[[1]]
#' f1 <- set_values(f0, entry.564397473 = "abc")
submit_form <- function(session, form, submit = NULL, ...) {
  request <- submit_request(form, submit)

  # Make request
  if (request$method == "GET") {
    request_GET(session, url = request$url, params = request$values, ...)
  } else if (request$method == "POST") {
    request_POST(session, url = request$url, body = request$values,
      encode = request$encode, ...)
  } else {
    stop("Unknown method: ", request$method, call. = FALSE)
  }
}

submit_request <- function(form, submit = NULL) {
  submits <- Filter(function(x) identical(x$type, "submit"), form$fields)
  if (is.null(submit)) {
    submit <- names(submits)[[1]]
    message("Submitting with '", submit, "'")
  }
  if (!(submit %in% names(submits))) {
    stop(
      "Unknown submission name '", submit, "'.\n",
      "Possible values: ", paste0(names(submits), collapse = ", "),
      call. = FALSE
    )
  }
  other_submits <- setdiff(names(submits), submit)

  # Parameters needed for http request -----------------------------------------
  method <- form$method
  if (!(method %in% c("POST", "GET"))) {
    warning("Invalid method (", method, "), defaulting to GET", call. = FALSE)
    method <- "GET"
  }

  url <- form$url

  fields <- form$fields
  fields <- Filter(function(x) !is.null(x$value), fields)
  fields <- fields[setdiff(names(fields), other_submits)]

  values <- pluck(fields, "value")
  names(values) <- names(fields)

  list(
    method = method,
    encode = form$enctype,
    url = url,
    values = values
  )
}

#' Make link to google form given id
#'
#' @param x Unique identifier for form
#' @export
#' @examples
#' google_form("1M9B8DsYNFyDjpwSK6ur_bZf8Rv_04ma3rmaaBiveoUI")
google_form <- function(x) {
  html(paste0("https://docs.google.com/forms/d/", x, "/viewform"))
}
