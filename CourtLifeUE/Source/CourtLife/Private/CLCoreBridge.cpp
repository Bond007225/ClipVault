#include "CLCoreBridge.h"

#include "Dom/JsonObject.h"
#include "Misc/Base64.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

#include <string>

static_assert(CLAttributeCount == courtlife::kAttrCount, "FMyPlayerBuild::Attributes must mirror courtlife::Attr");

namespace CLBridge
{
	static std::string ToStd(const FName Name) { return std::string(TCHAR_TO_UTF8(*Name.ToString())); }
	static FName FromStd(std::string_view Id) { return FName(UTF8_TO_TCHAR(std::string(Id).c_str())); }

	courtlife::Body ToCore(const FCLBody& B)
	{
		return courtlife::NormalizeBody({B.HeightIn, B.WeightLb, B.WingspanIn, B.Build});
	}

	courtlife::Attributes ToCore(const TArray<int32>& In)
	{
		courtlife::Attributes Out;
		Out.fill(60);
		for (int32 i = 0; i < courtlife::kAttrCount && i < In.Num(); ++i) Out[i] = In[i];
		return Out;
	}

	courtlife::JumpshotSettings ToCore(const FCLJumpshot& J)
	{
		courtlife::JumpshotSettings S;
		S.base = courtlife::FindShotBase(ToStd(J.Base));
		S.release1 = courtlife::FindShotRelease(ToStd(J.Release1));
		S.release2 = courtlife::FindShotRelease(ToStd(J.Release2));
		S.blend = J.Blend;
		S.speed = J.Speed;
		return courtlife::NormalizeJumpshot(S);
	}

	courtlife::DribbleCombo ToCore(const FCLDribbleCombo& C)
	{
		courtlife::DribbleCombo Out;
		Out.name = TCHAR_TO_UTF8(*C.Name);
		for (const FCLComboStep& Step : C.Steps)
		{
			const int Move = courtlife::FindDribbleMove(ToStd(Step.Move));
			if (Move >= 0) Out.steps.push_back({Move, Step.Speed});
		}
		return Out;
	}

	courtlife::Position ToCore(ECLPosition P)
	{
		return static_cast<courtlife::Position>(static_cast<uint8>(P));
	}

	int32 Rating(const FMyPlayerBuild& Build, courtlife::Attr Attr)
	{
		const int32 Index = static_cast<int32>(Attr);
		return Build.Attributes.IsValidIndex(Index) ? Build.Attributes[Index] : 60;
	}

	FCLShotProfile FromCore(const courtlife::ShotProfile& P)
	{
		FCLShotProfile Out;
		Out.DurationMs = P.durationMs;
		Out.ReleaseTimeMs = P.releaseTimeMs;
		Out.GreenWindowMs = P.greenWindowMs;
		Out.ReleaseHeightFt = P.releaseHeightFt;
		Out.ContestResist = P.contestResist;
		Out.Rhythm = P.rhythm;
		Out.PlayRate = P.playRate;
		Out.ReleaseBlend = P.releaseBlend;
		return Out;
	}

	ECLReleaseGrade FromCore(courtlife::ReleaseGrade G)
	{
		return static_cast<ECLReleaseGrade>(static_cast<uint8>(G));
	}

	ECLShotType FromCore(courtlife::FinishType T)
	{
		switch (T)
		{
		case courtlife::FinishType::Layup: return ECLShotType::Layup;
		case courtlife::FinishType::Dunk: return ECLShotType::Dunk;
		default: return ECLShotType::Jumper;
		}
	}

	courtlife::FinishType ToCore(ECLShotType T)
	{
		switch (T)
		{
		case ECLShotType::Layup: return courtlife::FinishType::Layup;
		case ECLShotType::Dunk: return courtlife::FinishType::Dunk;
		default: return courtlife::FinishType::None;
		}
	}
}

FMyPlayerBuild UCLBuildLibrary::MakeDefaultBuild()
{
	FMyPlayerBuild B;
	B.Attributes = {70, 75, 60, 72, 75, 75, 78, 75, 72, 65, 62, 40, 76, 76, 70, 50, 80};
	B.Outfit.Jersey = MakeGarment(TEXT("tank"), FLinearColor::FromSRGBColor(FColor::FromHex(TEXT("1d428a"))), FLinearColor::FromSRGBColor(FColor::FromHex(TEXT("ffc72c"))));
	B.Outfit.Shorts = MakeGarment(TEXT("standard"), B.Outfit.Jersey.Primary, B.Outfit.Jersey.Secondary);
	B.Outfit.Shoes = MakeGarment(TEXT("low"), FLinearColor::White, FLinearColor::FromSRGBColor(FColor::FromHex(TEXT("c8102e"))), FLinearColor::White);
	B.Outfit.Socks = MakeGarment(TEXT("crew"), FLinearColor::White);
	auto Combo = [](const TCHAR* Name, int32 Slot, std::initializer_list<FName> Moves)
	{
		FCLDribbleCombo C;
		C.Name = Name;
		C.Slot = Slot;
		for (FName M : Moves) C.Steps.Add(MakeComboStep(M, 1.f));
		return C;
	};
	B.Combos = {
		Combo(TEXT("Cross Step"), 0, {TEXT("crossover"), TEXT("stepBack")}),
		Combo(TEXT("Hesi Go"), 1, {TEXT("pound"), TEXT("hesitation")}),
		Combo(TEXT("Legs Behind"), 2, {TEXT("betweenLegs"), TEXT("behindBack")}),
		Combo(TEXT("Spin"), 3, {TEXT("spin")}),
	};
	return NormalizeBuild(B);
}

FMyPlayerBuild UCLBuildLibrary::NormalizeBuild(const FMyPlayerBuild& In)
{
	FMyPlayerBuild B = In;
	if (!B.Id.IsValid()) B.Id = FGuid::NewGuid();
	B.Name = B.Name.TrimStartAndEnd().Left(24);
	if (B.Name.IsEmpty()) B.Name = TEXT("Rookie");
	B.Number = FMath::Clamp(B.Number, 0, 99);

	const courtlife::Body Body = CLBridge::ToCore(B.Body);
	B.Body.HeightIn = Body.heightIn;
	B.Body.WeightLb = Body.weightLb;
	B.Body.WingspanIn = Body.wingspanIn;
	B.Body.Build = Body.build;

	const courtlife::Attributes Legal = courtlife::LegalizeAttributes(CLBridge::ToCore(B.Attributes), Body);
	B.Attributes.SetNum(CLAttributeCount);
	for (int32 i = 0; i < CLAttributeCount; ++i) B.Attributes[i] = Legal[i];

	const courtlife::JumpshotSettings J = CLBridge::ToCore(B.Jumpshot);
	B.Jumpshot.Base = CLBridge::FromStd(courtlife::ShotBases()[J.base].id);
	B.Jumpshot.Release1 = CLBridge::FromStd(courtlife::ShotReleases()[J.release1].id);
	B.Jumpshot.Release2 = CLBridge::FromStd(courtlife::ShotReleases()[J.release2].id);
	B.Jumpshot.Blend = J.blend;
	B.Jumpshot.Speed = J.speed;

	TSet<int32> UsedSlots;
	TArray<FCLDribbleCombo> Combos;
	for (FCLDribbleCombo C : B.Combos)
	{
		C.Steps.RemoveAll([](const FCLComboStep& S) { return courtlife::FindDribbleMove(CLBridge::ToStd(S.Move)) < 0; });
		if (C.Steps.Num() > courtlife::kMaxComboSteps) C.Steps.SetNum(courtlife::kMaxComboSteps);
		for (FCLComboStep& S : C.Steps) S.Speed = FMath::Clamp(S.Speed, courtlife::kMinStepSpeed, courtlife::kMaxStepSpeed);
		if (C.Steps.IsEmpty() || Combos.Num() >= courtlife::kMaxCombos) continue;
		C.Slot = FMath::Clamp(C.Slot, 0, courtlife::kMaxCombos - 1);
		while (UsedSlots.Contains(C.Slot)) C.Slot = (C.Slot + 1) % courtlife::kMaxCombos;
		UsedSlots.Add(C.Slot);
		C.Name = C.Name.Left(20);
		Combos.Add(MoveTemp(C));
	}
	B.Combos = MoveTemp(Combos);

	TMap<uint8, int32> PerSlot;
	B.Tattoos.RemoveAll([&PerSlot](const FCLTattoo& T) { return ++PerSlot.FindOrAdd(static_cast<uint8>(T.Slot)) > 3; });
	for (FCLTattoo& T : B.Tattoos)
	{
		T.Scale = FMath::Clamp(T.Scale, 0.4f, 1.6f);
		T.Offset = FMath::Clamp(T.Offset, 0.f, 1.f);
		T.Rotate = FMath::Clamp(T.Rotate, 0.f, 1.f);
		T.Text = T.Text.Left(16);
	}
	return B;
}

int32 UCLBuildLibrary::OverallRating(const FMyPlayerBuild& Build)
{
	return courtlife::OverallRating(CLBridge::ToCore(Build.Attributes), CLBridge::ToCore(Build.Position));
}

TArray<int32> UCLBuildLibrary::AttributeCaps(const FCLBody& Body)
{
	const courtlife::Attributes Caps = courtlife::AttributeCaps(CLBridge::ToCore(Body));
	return TArray<int32>(Caps.data(), static_cast<int32>(Caps.size()));
}

int32 UCLBuildLibrary::SetAttribute(const FMyPlayerBuild& Build, int32 AttributeIndex, int32 Value)
{
	if (AttributeIndex < 0 || AttributeIndex >= CLAttributeCount) return Value;
	return courtlife::SetAttribute(CLBridge::ToCore(Build.Attributes), CLBridge::ToCore(Build.Body),
		static_cast<courtlife::Attr>(AttributeIndex), Value);
}

FCLShotProfile UCLBuildLibrary::ComputeShotProfile(const FMyPlayerBuild& Build)
{
	using courtlife::Attr;
	const courtlife::ShotContext Ctx{CLBridge::Rating(Build, Attr::ThreePoint), CLBridge::Rating(Build, Attr::Vertical), Build.Body.HeightIn};
	return CLBridge::FromCore(courtlife::ComputeShotProfile(CLBridge::ToCore(Build.Jumpshot), Ctx));
}

ECLShotType UCLBuildLibrary::ChooseFinish(const FMyPlayerBuild& Build, float DistanceFt, float SpeedFtPerSec)
{
	return CLBridge::FromCore(courtlife::ChooseFinish(DistanceFt, SpeedFtPerSec, CLBridge::ToCore(Build.Attributes), Build.Body.HeightIn));
}

TArray<FString> UCLBuildLibrary::ValidateCombo(const FMyPlayerBuild& Build, const FCLDribbleCombo& Combo)
{
	TArray<FString> Out;
	for (const std::string& E : courtlife::ValidateCombo(CLBridge::ToCore(Combo), CLBridge::Rating(Build, courtlife::Attr::BallHandle)))
	{
		Out.Add(UTF8_TO_TCHAR(E.c_str()));
	}
	return Out;
}

// ------------------------------------------------------------------ build code import
namespace CLBuildCodeJson
{
	FLinearColor Hex(const TSharedPtr<FJsonObject>& O, const TCHAR* Field, FLinearColor Fallback)
	{
		FString S;
		return O.IsValid() && O->TryGetStringField(Field, S) ? FLinearColor::FromSRGBColor(FColor::FromHex(S)) : Fallback;
	}

	TSharedPtr<FJsonObject> Obj(const TSharedPtr<FJsonObject>& O, const TCHAR* Field)
	{
		const TSharedPtr<FJsonObject>* Out = nullptr;
		return O.IsValid() && O->TryGetObjectField(Field, Out) ? *Out : nullptr;
	}

	FName Str(const TSharedPtr<FJsonObject>& O, const TCHAR* Field, FName Fallback)
	{
		FString S;
		return O.IsValid() && O->TryGetStringField(Field, S) ? FName(*S) : Fallback;
	}

	double Num(const TSharedPtr<FJsonObject>& O, const TCHAR* Field, double Fallback)
	{
		double V;
		return O.IsValid() && O->TryGetNumberField(Field, V) ? V : Fallback;
	}

	const TCHAR* const AttributeKeys[CLAttributeCount] = {
		TEXT("closeShot"), TEXT("drivingLayup"), TEXT("drivingDunk"), TEXT("midRange"), TEXT("threePoint"), TEXT("freeThrow"),
		TEXT("ballHandle"), TEXT("speedWithBall"), TEXT("passAccuracy"), TEXT("perimeterDefense"), TEXT("steal"), TEXT("block"),
		TEXT("speed"), TEXT("acceleration"), TEXT("vertical"), TEXT("strength"), TEXT("stamina")};

	const TCHAR* const TattooSlotKeys[] = {
		TEXT("neck"), TEXT("leftUpperArm"), TEXT("rightUpperArm"), TEXT("leftForearm"), TEXT("rightForearm"),
		TEXT("leftHand"), TEXT("rightHand"), TEXT("leftCalf"), TEXT("rightCalf")};

	const TCHAR* const ComboKeys[] = {TEXT("1"), TEXT("2"), TEXT("3"), TEXT("4"), TEXT("Q"), TEXT("E"), TEXT("R"), TEXT("F")};
}

bool UCLBuildLibrary::ImportBuildCode(const FString& Code, FMyPlayerBuild& Out, FString& OutError)
{
	using namespace CLBuildCodeJson;
	const FString Trimmed = Code.TrimStartAndEnd();
	if (!Trimmed.StartsWith(TEXT("CL1.")))
	{
		OutError = TEXT("That is not a CourtLife build code.");
		return false;
	}
	TArray<uint8> Bytes;
	if (!FBase64::Decode(Trimmed.Mid(4), Bytes))
	{
		OutError = TEXT("Build code is damaged or incomplete.");
		return false;
	}
	const FString Json(FUTF8ToTCHAR(reinterpret_cast<const ANSICHAR*>(Bytes.GetData()), Bytes.Num()));
	TSharedPtr<FJsonObject> Root;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Json), Root) || !Root.IsValid())
	{
		OutError = TEXT("Build code is damaged or incomplete.");
		return false;
	}

	FMyPlayerBuild B;
	Root->TryGetStringField(TEXT("name"), B.Name);
	B.Number = static_cast<int32>(Num(Root, TEXT("number"), 0));
	const FName Pos = Str(Root, TEXT("position"), TEXT("PG"));
	const FName Positions[] = {TEXT("PG"), TEXT("SG"), TEXT("SF"), TEXT("PF"), TEXT("C")};
	for (int32 i = 0; i < 5; ++i) if (Pos == Positions[i]) B.Position = static_cast<ECLPosition>(i);

	const TSharedPtr<FJsonObject> Body = Obj(Root, TEXT("body"));
	B.Body.HeightIn = static_cast<int32>(Num(Body, TEXT("heightIn"), 75));
	B.Body.WeightLb = static_cast<int32>(Num(Body, TEXT("weightLb"), 190));
	B.Body.WingspanIn = static_cast<int32>(Num(Body, TEXT("wingspanIn"), B.Body.HeightIn + 3));
	B.Body.Build = static_cast<float>(Num(Body, TEXT("build"), 0.5));
	B.Body.SkinTone = Hex(Body, TEXT("skinTone"), B.Body.SkinTone);

	const TSharedPtr<FJsonObject> Face = Obj(Root, TEXT("face"));
	B.Face.HairStyle = Str(Face, TEXT("hairStyle"), B.Face.HairStyle);
	B.Face.HairColor = Hex(Face, TEXT("hairColor"), B.Face.HairColor);
	B.Face.FacialHair = Str(Face, TEXT("facialHair"), B.Face.FacialHair);
	B.Face.FacialHairColor = Hex(Face, TEXT("facialHairColor"), B.Face.FacialHairColor);
	B.Face.EyeColor = Hex(Face, TEXT("eyeColor"), B.Face.EyeColor);

	const TSharedPtr<FJsonObject> Outfit = Obj(Root, TEXT("outfit"));
	const TSharedPtr<FJsonObject> Jersey = Obj(Outfit, TEXT("jersey"));
	B.Outfit.Jersey = MakeGarment(Str(Jersey, TEXT("style"), TEXT("tank")), Hex(Jersey, TEXT("primary"), FLinearColor::Blue), Hex(Jersey, TEXT("secondary"), FLinearColor::Yellow));
	const TSharedPtr<FJsonObject> Shorts = Obj(Outfit, TEXT("shorts"));
	B.Outfit.Shorts = MakeGarment(Str(Shorts, TEXT("length"), TEXT("standard")), Hex(Shorts, TEXT("color"), FLinearColor::Blue), Hex(Shorts, TEXT("stripe"), FLinearColor::Yellow));
	const TSharedPtr<FJsonObject> Shoes = Obj(Outfit, TEXT("shoes"));
	B.Outfit.Shoes = MakeGarment(Str(Shoes, TEXT("model"), TEXT("low")), Hex(Shoes, TEXT("primary"), FLinearColor::White), Hex(Shoes, TEXT("accent"), FLinearColor::Red), Hex(Shoes, TEXT("sole"), FLinearColor::White));
	const TSharedPtr<FJsonObject> Socks = Obj(Outfit, TEXT("socks"));
	B.Outfit.Socks = MakeGarment(Str(Socks, TEXT("length"), TEXT("crew")), Hex(Socks, TEXT("color"), FLinearColor::White));
	if (const TSharedPtr<FJsonObject> Acc = Obj(Outfit, TEXT("accessories")))
	{
		const TSharedPtr<FJsonObject> Headband = Obj(Acc, TEXT("headband"));
		bool bOn = false;
		if (Headband.IsValid() && Headband->TryGetBoolField(TEXT("on"), bOn) && bOn)
			B.Outfit.Accessories.Add(MakeGarment(TEXT("headband"), Hex(Headband, TEXT("color"), FLinearColor::White)));
		for (const TCHAR* Sleeve : {TEXT("armSleeve"), TEXT("legSleeve")})
		{
			const TSharedPtr<FJsonObject> S = Obj(Acc, Sleeve);
			const FName Side = Str(S, TEXT("side"), TEXT("none"));
			if (Side != TEXT("none")) B.Outfit.Accessories.Add(MakeGarment(FName(*FString::Printf(TEXT("%s_%s"), Sleeve, *Side.ToString())), Hex(S, TEXT("color"), FLinearColor::Black)));
		}
		const TSharedPtr<FJsonObject> Wrist = Obj(Acc, TEXT("wristbands"));
		for (const TCHAR* Side : {TEXT("left"), TEXT("right")})
		{
			bool bWorn = false;
			if (Wrist.IsValid() && Wrist->TryGetBoolField(Side, bWorn) && bWorn)
				B.Outfit.Accessories.Add(MakeGarment(FName(*FString::Printf(TEXT("wristband_%s"), Side)), Hex(Wrist, TEXT("color"), FLinearColor::White)));
		}
	}

	const TArray<TSharedPtr<FJsonValue>>* Tattoos = nullptr;
	if (Root->TryGetArrayField(TEXT("tattoos"), Tattoos))
	{
		for (const TSharedPtr<FJsonValue>& V : *Tattoos)
		{
			const TSharedPtr<FJsonObject> T = V->AsObject();
			FCLTattoo Tat;
			const FName Slot = Str(T, TEXT("slot"), NAME_None);
			int32 SlotIndex = INDEX_NONE;
			for (int32 i = 0; i < static_cast<int32>(UE_ARRAY_COUNT(TattooSlotKeys)); ++i) if (Slot == TattooSlotKeys[i]) SlotIndex = i;
			if (SlotIndex == INDEX_NONE) continue;
			Tat.Slot = static_cast<ECLTattooSlot>(SlotIndex);
			Tat.Design = Str(T, TEXT("design"), Tat.Design);
			Tat.Ink = Hex(T, TEXT("color"), Tat.Ink);
			Tat.Accent = Hex(T, TEXT("accent"), Tat.Accent);
			Tat.Scale = static_cast<float>(Num(T, TEXT("scale"), 1));
			Tat.Offset = static_cast<float>(Num(T, TEXT("offset"), 0.5));
			Tat.Rotate = static_cast<float>(Num(T, TEXT("rotate"), 0));
			T->TryGetStringField(TEXT("text"), Tat.Text);
			B.Tattoos.Add(Tat);
		}
	}

	const TSharedPtr<FJsonObject> Attrs = Obj(Root, TEXT("attributes"));
	B.Attributes.SetNum(CLAttributeCount);
	for (int32 i = 0; i < CLAttributeCount; ++i) B.Attributes[i] = static_cast<int32>(Num(Attrs, AttributeKeys[i], 60));

	const TSharedPtr<FJsonObject> Js = Obj(Root, TEXT("jumpshot"));
	B.Jumpshot.Base = Str(Js, TEXT("base"), B.Jumpshot.Base);
	B.Jumpshot.Release1 = Str(Js, TEXT("release1"), B.Jumpshot.Release1);
	B.Jumpshot.Release2 = Str(Js, TEXT("release2"), B.Jumpshot.Release2);
	B.Jumpshot.Blend = static_cast<int32>(Num(Js, TEXT("blend"), 30));
	B.Jumpshot.Speed = static_cast<int32>(Num(Js, TEXT("speed"), 3));

	const TArray<TSharedPtr<FJsonValue>>* Combos = nullptr;
	if (Root->TryGetArrayField(TEXT("combos"), Combos))
	{
		for (const TSharedPtr<FJsonValue>& V : *Combos)
		{
			const TSharedPtr<FJsonObject> C = V->AsObject();
			FCLDribbleCombo Combo;
			if (C.IsValid()) C->TryGetStringField(TEXT("name"), Combo.Name);
			const FName Key = Str(C, TEXT("key"), TEXT("1"));
			for (int32 i = 0; i < static_cast<int32>(UE_ARRAY_COUNT(ComboKeys)); ++i) if (Key == ComboKeys[i]) Combo.Slot = i;
			const TArray<TSharedPtr<FJsonValue>>* Steps = nullptr;
			if (C.IsValid() && C->TryGetArrayField(TEXT("steps"), Steps))
			{
				for (const TSharedPtr<FJsonValue>& SV : *Steps)
				{
					const TSharedPtr<FJsonObject> S = SV->AsObject();
					Combo.Steps.Add(MakeComboStep(Str(S, TEXT("move"), TEXT("crossover")), static_cast<float>(Num(S, TEXT("speed"), 1))));
				}
			}
			B.Combos.Add(MoveTemp(Combo));
		}
	}

	Out = NormalizeBuild(B);
	return true;
}
