#= require_tree .

$(".menu").click ->
  $(".main-navigation").slideToggle("fast")
  return false
