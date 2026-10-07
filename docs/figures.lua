-- Ancho de cada figura en el PDF, según el nombre del archivo.
-- Width of each figure in the PDF, by file name.
local widths = {
  ["architecture"] = "100%",
  ["panel"] = "40%",
  ["printout"] = "100%",
  ["typefaces"] = "100%",
}

function Image(img)
  for name, width in pairs(widths) do
    if img.src:find(name, 1, true) then
      img.attributes.width = width
    end
  end
  return img
end
