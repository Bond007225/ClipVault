#include "CLCustomizationComponent.h"

#include "CLAssets.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/Canvas.h"
#include "Engine/Font.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/Texture2D.h"
#include "Engine/TextureRenderTarget2D.h"
#include "GameFramework/Character.h"
#include "Kismet/KismetRenderingLibrary.h"
#include "Materials/MaterialInstanceDynamic.h"

USkeletalMeshComponent* UCLCustomizationComponent::GetBody() const
{
	const ACharacter* Character = Cast<ACharacter>(GetOwner());
	return Character ? Character->GetMesh() : nullptr;
}

void UCLCustomizationComponent::ClearEquipped()
{
	for (auto& Pair : Equipped)
	{
		if (Pair.Value) Pair.Value->DestroyComponent();
	}
	Equipped.Reset();
}

USkeletalMeshComponent* UCLCustomizationComponent::Equip(FName SlotName, const FCLCosmeticItem* Item, const FCLGarment* Colors)
{
	USkeletalMeshComponent* Body = GetBody();
	if (!Body || !Item) return nullptr;
	USkeletalMesh* Mesh = Item->Mesh.LoadSynchronous();  // TODO: async-load via the asset manager for shipping
	if (!Mesh) return nullptr;

	USkeletalMeshComponent* Comp = NewObject<USkeletalMeshComponent>(GetOwner(), MakeUniqueObjectName(GetOwner(), USkeletalMeshComponent::StaticClass(), SlotName));
	Comp->SetSkeletalMesh(Mesh);
	Comp->SetupAttachment(Body);
	Comp->RegisterComponent();
	Comp->SetLeaderPoseComponent(Body);
	if (UMaterialInterface* Mat = Item->Material.LoadSynchronous()) Comp->SetMaterial(0, Mat);
	if (Colors)
	{
		for (int32 i = 0; i < Comp->GetNumMaterials(); ++i)
		{
			UMaterialInstanceDynamic* MID = Comp->CreateDynamicMaterialInstance(i);
			MID->SetVectorParameterValue(TEXT("Primary"), Colors->Primary);
			MID->SetVectorParameterValue(TEXT("Secondary"), Colors->Secondary);
			MID->SetVectorParameterValue(TEXT("Tertiary"), Colors->Tertiary);
		}
	}
	Equipped.Add(SlotName, Comp);
	return Comp;
}

void UCLCustomizationComponent::ApplyBuild(const FMyPlayerBuild& Build, UCLCosmeticsCatalog* Catalog)
{
	USkeletalMeshComponent* Body = GetBody();
	if (!Body || !Catalog) return;
	ActiveCatalog = Catalog;
	ClearEquipped();

	// Proportions: uniform height scale plus morphs for mass. Wingspan is
	// handled by an arm-length bone scale in the post-process anim BP.
	const float HeightScale = Build.Body.HeightIn / ReferenceHeightIn;
	Body->SetRelativeScale3D(FVector(HeightScale));
	Body->SetMorphTarget(HeavyMorph, FMath::GetMappedRangeValueClamped(FVector2f(160.f, 290.f), FVector2f(0.f, 1.f), static_cast<float>(Build.Body.WeightLb)));
	Body->SetMorphTarget(MuscleMorph, Build.Body.Build);

	SkinMaterials.Reset();
	for (int32 i = 0; i < Body->GetNumMaterials(); ++i)
	{
		UMaterialInstanceDynamic* MID = Body->CreateDynamicMaterialInstance(i);
		MID->SetVectorParameterValue(TEXT("SkinTone"), Build.Body.SkinTone);
		MID->SetVectorParameterValue(TEXT("EyeColor"), Build.Face.EyeColor);
		SkinMaterials.Add(MID);
	}

	auto Hair = [](const FLinearColor& C) { FCLGarment G; G.Primary = C; return G; };
	const FCLGarment HairColors = Hair(Build.Face.HairColor);
	const FCLGarment BeardColors = Hair(Build.Face.FacialHairColor);
	Equip(TEXT("Hair"), Catalog->HairStyles.Find(Build.Face.HairStyle), &HairColors);
	Equip(TEXT("FacialHair"), Catalog->FacialHair.Find(Build.Face.FacialHair), &BeardColors);
	Equip(TEXT("Jersey"), Catalog->Jerseys.Find(Build.Outfit.Jersey.Item), &Build.Outfit.Jersey);
	Equip(TEXT("Shorts"), Catalog->Shorts.Find(Build.Outfit.Shorts.Item), &Build.Outfit.Shorts);
	Equip(TEXT("Shoes"), Catalog->Shoes.Find(Build.Outfit.Shoes.Item), &Build.Outfit.Shoes);
	Equip(TEXT("Socks"), Catalog->Socks.Find(Build.Outfit.Socks.Item), &Build.Outfit.Socks);
	for (const FCLGarment& Acc : Build.Outfit.Accessories)
	{
		Equip(FName(*FString::Printf(TEXT("Acc_%s"), *Acc.Item.ToString())), Catalog->Accessories.Find(Acc.Item), &Acc);
	}
	if (USkeletalMeshComponent* Jersey = Equipped.FindRef(TEXT("Jersey")))
	{
		for (int32 i = 0; i < Jersey->GetNumMaterials(); ++i)
		{
			if (UMaterialInstanceDynamic* MID = Cast<UMaterialInstanceDynamic>(Jersey->GetMaterial(i)))
				MID->SetScalarParameterValue(TEXT("Number"), static_cast<float>(Build.Number));
		}
	}

	RepaintTattoos(Build.Tattoos, Build.Number);
}

void UCLCustomizationComponent::RepaintTattoos(const TArray<FCLTattoo>& Tattoos, int32 JerseyNumber)
{
	UCLCosmeticsCatalog* Catalog = ActiveCatalog;
	if (!Catalog) return;
	const int32 Size = FMath::Clamp(Catalog->TattooAtlasSize, 256, 4096);
	if (!TattooAtlas)
	{
		TattooAtlas = UKismetRenderingLibrary::CreateRenderTarget2D(this, Size, Size, RTF_RGBA8, FLinearColor::Transparent);
	}
	UKismetRenderingLibrary::ClearRenderTarget2D(this, TattooAtlas, FLinearColor::Transparent);

	UCanvas* Canvas = nullptr;
	FVector2D CanvasSize;
	FDrawToRenderTargetContext Context;
	UKismetRenderingLibrary::BeginDrawCanvasToRenderTarget(this, TattooAtlas, Canvas, CanvasSize, Context);

	for (const FCLTattoo& T : Tattoos)
	{
		const int32 SlotIndex = static_cast<int32>(T.Slot);
		const FCLTattooDesign* Design = Catalog->TattooDesigns.Find(T.Design);
		if (!Design || !Catalog->TattooRegions.IsValidIndex(SlotIndex)) continue;
		const FCLTattooRegion& Region = Catalog->TattooRegions[SlotIndex];

		// Region in pixels. U wraps around the limb (0 = front), V runs down it.
		const FVector2D Min = Region.UV.Min * CanvasSize;
		const FVector2D Extent = (Region.UV.Max - Region.UV.Min) * CanvasSize;
		const double DesignV = Extent.Y * 0.33 * T.Scale;            // design height
		const double DesignU = DesignV * Extent.X / (Extent.Y * FMath::Max(0.1f, Region.Aspect));
		const FVector2D Center(Min.X + T.Rotate * Extent.X, Min.Y + (0.12 + T.Offset * 0.76) * Extent.Y);

		if (Design->bDrawsText)
		{
			const FString Text = T.Text.IsEmpty() ? (T.Design == TEXT("number") ? FString::FromInt(JerseyNumber) : FString(TEXT("Hooper"))) : T.Text;
			if (UFont* Font = Catalog->ScriptFont)
			{
				const double TextScale = DesignV / FMath::Max(1.f, Font->GetMaxCharHeight());
				Canvas->K2_DrawText(Font, Text, Center, FVector2D(TextScale, TextScale), T.Ink, 0.f, FLinearColor::Transparent,
					FVector2D::ZeroVector, true, true, false, FLinearColor::Transparent);
			}
			continue;
		}
		UTexture2D* Stencil = Design->Stencil.LoadSynchronous();
		if (!Stencil) continue;
		if (Design->bWrapsLimb)
		{
			const FVector2D Pos(Min.X, Center.Y - DesignV * 0.5);
			Canvas->K2_DrawTexture(Stencil, Pos, FVector2D(Extent.X, DesignV), FVector2D::ZeroVector, FVector2D(Extent.X / DesignU, 1.0), T.Ink);
			continue;
		}
		// Draw a second copy shifted by one wrap so designs crossing the
		// region's seam continue on the other side of the limb.
		for (const double Shift : {0.0, -Extent.X, Extent.X})
		{
			const FVector2D Pos(Center.X + Shift - DesignU * 0.5, Center.Y - DesignV * 0.5);
			if (Pos.X + DesignU < Min.X || Pos.X > Min.X + Extent.X) continue;
			Canvas->K2_DrawTexture(Stencil, Pos, FVector2D(DesignU, DesignV), FVector2D::ZeroVector, FVector2D::UnitVector, T.Ink);
		}
	}
	UKismetRenderingLibrary::EndDrawCanvasToRenderTarget(this, Context);

	for (UMaterialInstanceDynamic* MID : SkinMaterials)
	{
		MID->SetTextureParameterValue(TEXT("TattooAtlas"), TattooAtlas);
	}
}
