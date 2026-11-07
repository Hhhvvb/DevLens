from io import BytesIO

from PIL import Image, ImageOps

MAX_AVATAR_UPLOAD_BYTES = 1024 * 1024

def prepare_avatar(data: bytes) -> bytes:
    try:
        with Image.open(BytesIO(data), formats=["JPEG"]) as source:
            if max(source.size) > 4096:
                raise ValueError("头像图片的宽和高都必须在 4096 像素以内。")

            image = ImageOps.exif_transpose(source).convert("RGB")
            image.thumbnail((512, 512))
    except (OSError, Image.DecompressionBombError) as error:
        raise ValueError("无法读取头像，请选择有效的 JPEG 图片。") from error

    clean_image = Image.new("RGB", image.size)
    clean_image.paste(image)

    with BytesIO() as output:
        clean_image.save(output, format="JPEG", quality=85)
        return output.getvalue()