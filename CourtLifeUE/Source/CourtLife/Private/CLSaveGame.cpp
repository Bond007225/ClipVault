#include "CLSaveGame.h"

#include "CLCoreBridge.h"
#include "Kismet/GameplayStatics.h"

static const TCHAR* const CLSaveSlot = TEXT("MyPlayers");

UCLSaveGame* UCLSaveGame::LoadOrCreate(int32 UserIndex)
{
	if (UCLSaveGame* Existing = Cast<UCLSaveGame>(UGameplayStatics::LoadGameFromSlot(CLSaveSlot, UserIndex)))
	{
		for (FMyPlayerBuild& P : Existing->Players) P = UCLBuildLibrary::NormalizeBuild(P);
		return Existing;
	}
	return Cast<UCLSaveGame>(UGameplayStatics::CreateSaveGameObject(UCLSaveGame::StaticClass()));
}

bool UCLSaveGame::Upsert(const FMyPlayerBuild& Build)
{
	const FMyPlayerBuild Clean = UCLBuildLibrary::NormalizeBuild(Build);
	if (FMyPlayerBuild* Found = Players.FindByPredicate([&](const FMyPlayerBuild& P) { return P.Id == Clean.Id; }))
	{
		*Found = Clean;
		return true;
	}
	if (Players.Num() >= MaxSlots) return false;
	Players.Add(Clean);
	return true;
}

void UCLSaveGame::Remove(const FGuid& Id)
{
	Players.RemoveAll([&](const FMyPlayerBuild& P) { return P.Id == Id; });
}

bool UCLSaveGame::Commit(int32 UserIndex)
{
	return UGameplayStatics::SaveGameToSlot(this, CLSaveSlot, UserIndex);
}
