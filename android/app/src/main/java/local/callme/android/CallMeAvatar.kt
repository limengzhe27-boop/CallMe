package local.callme.android

import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text

@Composable
fun CallMeAvatar(
    name: String,
    avatarUri: String,
    size: Int,
    fallbackBackground: Color,
    fallbackForeground: Color
) {
    val context = LocalContext.current
    val bitmap = remember(avatarUri) {
        if (avatarUri.isBlank()) null else runCatching {
            val uri = Uri.parse(avatarUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
        }.getOrNull()
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = "$name 的头像",
            modifier = Modifier.size(size.dp).clip(CircleShape),
            contentScale = ContentScale.Crop
        )
    } else {
        Box(
            modifier = Modifier.size(size.dp).background(fallbackBackground, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                name.trim().take(1).ifEmpty { "?" },
                color = fallbackForeground,
                fontSize = (size * 0.40f).sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
fun CallMeSquareAvatar(
    name: String,
    avatarUri: String,
    size: Int
) {
    val context = LocalContext.current
    val bitmap = remember(avatarUri) {
        if (avatarUri.isBlank()) null else runCatching {
            val uri = Uri.parse(avatarUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
        }.getOrNull()
    }
    val shape = RoundedCornerShape((size * 0.10f).dp)
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = "$name 的头像",
            modifier = Modifier.size(size.dp).clip(shape),
            contentScale = ContentScale.Crop
        )
    } else {
        Box(
            modifier = Modifier.size(size.dp).background(Color(0xFF4A4658), shape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                name.trim().take(1).ifEmpty { "?" },
                color = Color.White,
                fontSize = (size * 0.40f).sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
fun CallMeAvatarBackdrop(
    name: String,
    avatarUri: String,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val bitmap = remember(avatarUri) {
        if (avatarUri.isBlank()) null else runCatching {
            val uri = Uri.parse(avatarUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri))
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
            }
        }.getOrNull()
    }
    Box(modifier = modifier.background(Color(0xFF151414)), contentAlignment = Alignment.Center) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize().blur(30.dp),
                contentScale = ContentScale.Crop
            )
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.56f)))
        } else {
            Text(
                name.trim().take(1).ifEmpty { "?" },
                color = Color.White.copy(alpha = 0.06f),
                fontSize = 160.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.blur(12.dp)
            )
        }
    }
}
